from __future__ import annotations

import importlib
import json
import logging
import math
import os
from dataclasses import asdict, is_dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Any, Callable, Mapping, Sequence

from .binance import BinanceOrderResult
from .models import PlannedOrder, RebalanceDecision, RiskAction
from .tradingview import TradingViewAlert, TradingViewServerDecision


logger = logging.getLogger(__name__)

_WARNED_NO_DATABASE = False
_WARNED_NO_DRIVER = False

_PG_ENV_KEYS = (
    "PGHOST",
    "PGPORT",
    "PGDATABASE",
    "PGUSER",
    "PGPASSWORD",
    "PGSERVICE",
)


def record_decision(
    decision: RebalanceDecision,
    snapshot: Mapping[str, Any],
    *,
    mode: str,
) -> int | None:
    try:
        record = _decision_record_from_engine(decision, mode=mode)
        return _insert_decision_record(
            record=record,
            snapshot=snapshot,
            planned_orders=decision.orders,
            executions=(),
        )
    except Exception as exc:
        logger.warning("DB decision recording failed: %s", exc)
        return None


def record_paper_decision(
    *,
    alert: TradingViewAlert,
    decision: TradingViewServerDecision,
    snapshot: Mapping[str, Any],
    planned_orders: Sequence[Mapping[str, Any]],
    executions: Sequence[Mapping[str, Any]],
) -> int | None:
    try:
        record = _decision_record_from_tradingview(alert, decision, mode="paper")
        return _insert_decision_record(
            record=record,
            snapshot=snapshot,
            planned_orders=planned_orders,
            executions=executions,
        )
    except Exception as exc:
        logger.warning("DB paper decision recording failed: %s", exc)
        return None


def record_executions(
    decision_id: int | None,
    executions: Sequence[BinanceOrderResult | Mapping[str, Any]],
) -> None:
    if decision_id is None or not executions:
        return

    try:
        _with_connection(lambda conn: _insert_executions(conn, decision_id, executions))
    except Exception as exc:
        logger.warning("DB execution recording failed: %s", exc)


def _insert_decision_record(
    *,
    record: Mapping[str, Any],
    snapshot: Mapping[str, Any],
    planned_orders: Sequence[PlannedOrder | Mapping[str, Any]],
    executions: Sequence[BinanceOrderResult | Mapping[str, Any]],
) -> int | None:
    def write(conn: Any) -> int:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO decisions (
                    ts, mode, regime, raw_regime, market_bias, regime_score,
                    should_rebalance, risk_action, reasons, next_state
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CAST(%s AS jsonb), CAST(%s AS jsonb))
                RETURNING id
                """,
                (
                    record["ts"],
                    record["mode"],
                    record["regime"],
                    record["raw_regime"],
                    record["market_bias"],
                    record["regime_score"],
                    record["should_rebalance"],
                    record["risk_action"],
                    _jsonb(record["reasons"]),
                    _jsonb(record["next_state"]),
                ),
            )
            decision_id = int(cursor.fetchone()[0])
            cursor.execute(
                """
                INSERT INTO market_snapshots (
                    decision_id, ts, account, positions, candidates, btc, market_internals
                )
                VALUES (
                    %s, %s, CAST(%s AS jsonb), CAST(%s AS jsonb), CAST(%s AS jsonb),
                    CAST(%s AS jsonb), CAST(%s AS jsonb)
                )
                """,
                (
                    decision_id,
                    record["ts"],
                    _jsonb(snapshot.get("account", {})),
                    _jsonb(snapshot.get("positions", [])),
                    _jsonb(snapshot.get("candidates", [])),
                    _jsonb(snapshot.get("btc")),
                    _jsonb(snapshot.get("market_internals", {})),
                ),
            )
            for order in planned_orders:
                row = _planned_order_row(order)
                cursor.execute(
                    """
                    INSERT INTO planned_orders (decision_id, symbol, side, qty, type, meta)
                    VALUES (%s, %s, %s, %s, %s, CAST(%s AS jsonb))
                    """,
                    (
                        decision_id,
                        row["symbol"],
                        row["side"],
                        row["qty"],
                        row["type"],
                        _jsonb(row["meta"]),
                    ),
                )
            _insert_executions(conn, decision_id, executions, cursor=cursor)
            _insert_trade_results(conn, decision_id, executions, cursor=cursor)
            return decision_id

    return _with_connection(write)


def _insert_executions(
    conn: Any,
    decision_id: int,
    executions: Sequence[BinanceOrderResult | Mapping[str, Any]],
    *,
    cursor: Any | None = None,
) -> None:
    if not executions:
        return

    def write(active_cursor: Any) -> None:
        for execution in executions:
            row = _execution_row(execution)
            if row is None:
                continue
            active_cursor.execute(
                """
                INSERT INTO executions (decision_id, symbol, side, qty, price, fee, ts)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    decision_id,
                    row["symbol"],
                    row["side"],
                    row["qty"],
                    row["price"],
                    row["fee"],
                    row["ts"],
                ),
            )

    if cursor is not None:
        write(cursor)
        return

    with conn.cursor() as active_cursor:
        write(active_cursor)


def _insert_trade_results(
    conn: Any,
    decision_id: int,
    executions: Sequence[BinanceOrderResult | Mapping[str, Any]],
    *,
    cursor: Any | None = None,
) -> None:
    if not executions:
        return

    def write(active_cursor: Any) -> None:
        for execution in executions:
            row = _trade_result_row(execution)
            if row is None:
                continue
            active_cursor.execute(
                """
                INSERT INTO trade_results (
                    decision_id, symbol, realized_pnl, opened_at, closed_at, status
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    decision_id,
                    row["symbol"],
                    row["realized_pnl"],
                    row["opened_at"],
                    row["closed_at"],
                    row["status"],
                ),
            )

    if cursor is not None:
        write(cursor)
        return

    with conn.cursor() as active_cursor:
        write(active_cursor)


def _decision_record_from_engine(decision: RebalanceDecision, *, mode: str) -> dict[str, Any]:
    return {
        "ts": decision.now,
        "mode": _normalize_mode(mode),
        "regime": decision.regime.value,
        "raw_regime": decision.raw_regime.value,
        "market_bias": decision.market_bias.value,
        "regime_score": decision.regime_score,
        "should_rebalance": decision.should_rebalance,
        "risk_action": decision.risk_action.value,
        "reasons": list(decision.reasons),
        "next_state": decision.next_state,
    }


def _decision_record_from_tradingview(
    alert: TradingViewAlert,
    decision: TradingViewServerDecision,
    *,
    mode: str,
) -> dict[str, Any]:
    decided_alert = alert.with_server_decision(decision)
    regime, market_bias = decided_alert.to_regime_bias()
    return {
        "ts": _timestamp_from_ms(alert.time_ms),
        "mode": _normalize_mode(mode),
        "regime": regime.value,
        "raw_regime": regime.value,
        "market_bias": market_bias.value,
        "regime_score": decision.score,
        "should_rebalance": decision.action.value != "HOLD",
        "risk_action": RiskAction.NONE.value,
        "reasons": [
            decision.reason,
            f"TradingView source_regime={decision.source_regime.value}",
            f"TradingView action={decision.action.value}",
        ],
        "next_state": {
            "source": "tradingview",
            "signal_id": decided_alert.dedupe_key(),
            "decision_action": decision.action.value,
            "target_leverage": decision.target_leverage,
        },
    }


def _planned_order_row(order: PlannedOrder | Mapping[str, Any]) -> dict[str, Any]:
    if isinstance(order, PlannedOrder):
        return {
            "symbol": order.symbol,
            "side": order.side.value,
            "qty": None,
            "type": order.order_type.value,
            "meta": {
                "position_side": order.position_side.value,
                "notional": order.notional,
                "reduce_only": order.reduce_only,
                "reason": order.reason,
            },
        }

    return {
        "symbol": str(order.get("symbol", "")),
        "side": str(order.get("action") or order.get("side") or ""),
        "qty": _numeric(order.get("quantity") or order.get("qty")),
        "type": str(order.get("order_type") or order.get("type") or "MARKET"),
        "meta": dict(order),
    }


def _execution_row(execution: BinanceOrderResult | Mapping[str, Any]) -> dict[str, Any] | None:
    if isinstance(execution, BinanceOrderResult):
        response = execution.response or {}
        return {
            "symbol": execution.symbol,
            "side": execution.side,
            "qty": _numeric(execution.quantity),
            "price": _first_positive_numeric(
                response.get("avgPrice"),
                response.get("price"),
                response.get("reference_price"),
            ),
            "fee": None,
            "ts": _timestamp_from_ms(response.get("updateTime") or response.get("transactTime")),
        }

    symbol = str(execution.get("symbol", ""))
    side = str(execution.get("action") or execution.get("side") or "")
    if not symbol or not side:
        return None
    price = _numeric(execution.get("price"))
    qty = _numeric(execution.get("quantity") or execution.get("qty"))
    if qty is None and price is not None and price > 0:
        notional = _numeric(execution.get("notional"))
        if notional is not None:
            qty = abs(notional / price)
    fee_value = execution["fee"] if "fee" in execution else execution.get("cost")
    return {
        "symbol": symbol,
        "side": side,
        "qty": qty,
        "price": price,
        "fee": _numeric(fee_value),
        "ts": _parse_timestamp(execution.get("time")),
    }


def _trade_result_row(execution: BinanceOrderResult | Mapping[str, Any]) -> dict[str, Any] | None:
    if isinstance(execution, BinanceOrderResult) or not isinstance(execution, Mapping):
        return None

    action = str(execution.get("action") or "").upper()
    if action not in {"CLOSE", "REDUCE"}:
        return None

    symbol = str(execution.get("symbol") or "")
    if not symbol:
        return None

    realized = _numeric(execution.get("net_pnl"))
    if realized is None:
        gross = _numeric(execution.get("gross_pnl")) or Decimal("0")
        fee = _numeric(execution.get("fee")) or Decimal("0")
        slippage = _numeric(execution.get("slippage")) or Decimal("0")
        cost = _numeric(execution.get("cost"))
        realized = gross - (cost if cost is not None else fee + slippage)

    return {
        "symbol": symbol,
        "realized_pnl": realized,
        "opened_at": _parse_optional_timestamp(execution.get("opened_at")),
        "closed_at": _parse_timestamp(execution.get("time")),
        "status": "realized",
    }


def _with_connection(write: Callable[[Any], Any]) -> Any:
    driver = _load_driver()
    if driver is None:
        return None

    connect, dsn = driver
    if dsn is None and not _has_pg_env():
        _warn_no_database()
        return None

    conn = connect(dsn or "")
    try:
        result = write(conn)
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _load_driver() -> tuple[Callable[[str], Any], str | None] | None:
    global _WARNED_NO_DRIVER
    for name in ("psycopg", "psycopg2"):
        try:
            module = importlib.import_module(name)
        except ImportError:
            continue
        return module.connect, _database_dsn()

    if not _WARNED_NO_DRIVER:
        logger.warning("DB recording disabled: psycopg/psycopg2 is not installed")
        _WARNED_NO_DRIVER = True
    return None


def _database_dsn() -> str | None:
    for name in (
        "DATABASE_URL",
        "POSTGRES_DSN",
        "POSTGRES_URL",
        "LEARNING_DATABASE_URL",
        "RECORDING_DATABASE_URL",
    ):
        value = os.environ.get(name)
        if value:
            return value
    return None


def _has_pg_env() -> bool:
    return any(os.environ.get(name) for name in _PG_ENV_KEYS)


def _warn_no_database() -> None:
    global _WARNED_NO_DATABASE
    if not _WARNED_NO_DATABASE:
        logger.warning("DB recording disabled: no PostgreSQL DSN or PG* environment variables are set")
        _WARNED_NO_DATABASE = True


def _normalize_mode(mode: str) -> str:
    return "live" if mode == "live" else "paper"


def _jsonb(value: Any) -> str:
    return json.dumps(_to_json(value), ensure_ascii=False, separators=(",", ":"))


def _to_json(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, Decimal):
        return float(value) if value.is_finite() else None
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Enum):
        return value.value
    if hasattr(value, "to_payload") and callable(value.to_payload):
        return _to_json(value.to_payload())
    if is_dataclass(value):
        return _to_json(asdict(value))
    if isinstance(value, Mapping):
        return {str(key): _to_json(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_to_json(item) for item in value]
    return str(value)


def _numeric(value: Any) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not parsed.is_finite():
        return None
    return parsed


def _first_positive_numeric(*values: Any) -> Decimal | None:
    for value in values:
        parsed = _numeric(value)
        if parsed is not None and parsed > 0:
            return parsed
    return None


def _timestamp_from_ms(value: Any) -> datetime:
    parsed = _numeric(value)
    if parsed is None or parsed <= 0:
        return datetime.now(timezone.utc)
    return datetime.fromtimestamp(float(parsed) / 1000, tz=timezone.utc)


def _parse_timestamp(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str) and value:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _parse_optional_timestamp(value: Any) -> datetime | None:
    if value is None or value == "":
        return None
    return _parse_timestamp(value)
