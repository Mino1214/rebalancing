from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from .binance import BinanceFuturesClient
from .market_internals import apply_market_cap_dominance, build_market_internals
from .models import MarketBias, MarketCandidate, OrderSide, PositionSide, TargetPosition, TradeMode
from .portfolio import PortfolioBuilder
from .tradingview import TradingViewAlert, TradingViewRegime


def paper_trading_enabled() -> bool:
    return os.environ.get("PAPER_TRADING_ENABLED", "true").lower() == "true"


def paper_state_path() -> Path:
    return Path(os.environ.get("PAPER_STATE_PATH", ".state/paper_trading.json"))


def process_paper_alert(payload: Mapping[str, Any], *, path: Path | None = None) -> dict[str, Any]:
    alert = TradingViewAlert.parse(payload)
    state_path = path or paper_state_path()
    state = _load_state(state_path)
    client = BinanceFuturesClient()
    candidates = _market_candidates(client)
    equity_before = _marked_equity(state, client)
    targets = _targets_for_alert(alert, equity_before, candidates)
    target_symbols = {target.symbol for target in targets}
    position_symbols = {item["symbol"] for item in state.get("positions", [])}
    prices = _prices(client, target_symbols | position_symbols)

    update = _rebalance_state(
        state=state,
        alert=alert,
        targets=targets,
        prices=prices,
    )
    _write_state(state_path, update)
    return paper_status_payload(path=state_path) or update


def paper_status_payload(*, path: Path | None = None) -> dict[str, Any] | None:
    state_path = path or paper_state_path()
    state = _load_state(state_path)
    if not state.get("last_signal"):
        return None

    client = BinanceFuturesClient()
    symbols = {item["symbol"] for item in state.get("positions", [])}
    prices = _prices(client, symbols) if symbols else {}
    marked = _mark_state(state, prices)
    return _state_payload(marked)


def _market_candidates(client: BinanceFuturesClient) -> list[MarketCandidate]:
    candidates = client.market_candidates()
    try:
        internals = build_market_internals(binance=client, candidates=candidates)
        return apply_market_cap_dominance(candidates, internals)
    except Exception:
        return candidates


def _targets_for_alert(
    alert: TradingViewAlert,
    equity: float,
    candidates: list[MarketCandidate],
) -> tuple[TargetPosition, ...]:
    leverage = max(0.0, min(alert.target_leverage, _env_float("PAPER_MAX_LEVERAGE", 2.0)))
    if leverage <= 0 or alert.regime in {TradingViewRegime.RANGE, TradingViewRegime.CHAOTIC}:
        return tuple()

    builder = PortfolioBuilder()
    target_notional = equity * leverage

    if alert.regime == TradingViewRegime.TOP10_LONG:
        symbols = [item.symbol for item in builder.select_long_universe(candidates)]
        return _weighted_targets(
            symbols=symbols,
            side=PositionSide.LONG,
            target_notional=target_notional,
            core_weights={"BTCUSDT": 0.25, "ETHUSDT": 0.20},
            residual_weight=0.55,
        )

    if alert.regime == TradingViewRegime.BTC_ETH_LONG:
        eligible = {item.symbol: item for item in builder.select_long_universe(candidates)}
        symbols = [symbol for symbol in ("BTCUSDT", "ETHUSDT") if symbol in eligible]
        if not symbols:
            symbols = [item.symbol for item in builder.select_long_universe(candidates)[:2]]
        return _weighted_targets(
            symbols=symbols,
            side=PositionSide.LONG,
            target_notional=target_notional,
            core_weights={"BTCUSDT": 0.65, "ETHUSDT": 0.35},
            residual_weight=0.0,
        )

    symbols = [item.symbol for item in builder.select_short_universe(candidates)]
    if alert.regime == TradingViewRegime.ALT_WEAK_SHORT:
        return _weighted_targets(
            symbols=symbols,
            side=PositionSide.SHORT,
            target_notional=target_notional,
            core_weights={"BTCUSDT": 0.35, "ETHUSDT": 0.25},
            residual_weight=0.40,
        )

    return _weighted_targets(
        symbols=symbols,
        side=PositionSide.SHORT,
        target_notional=target_notional,
        core_weights={"BTCUSDT": 0.40, "ETHUSDT": 0.30},
        residual_weight=0.30,
    )


def _weighted_targets(
    *,
    symbols: list[str],
    side: PositionSide,
    target_notional: float,
    core_weights: dict[str, float],
    residual_weight: float,
) -> tuple[TargetPosition, ...]:
    if not symbols or target_notional <= 0:
        return tuple()

    symbol_set = set(symbols)
    weights: dict[str, float] = {}
    missing_weight = 0.0
    for symbol, weight in core_weights.items():
        if symbol in symbol_set:
            weights[symbol] = weight
        else:
            missing_weight += weight

    residual_symbols = [symbol for symbol in symbols if symbol not in weights]
    residual_total = residual_weight + missing_weight
    if residual_symbols:
        each = residual_total / len(residual_symbols)
        weights.update({symbol: each for symbol in residual_symbols})
    elif weights:
        scale = 1 / sum(weights.values())
        weights = {symbol: weight * scale for symbol, weight in weights.items()}

    total_weight = sum(weights.values())
    if total_weight <= 0:
        return tuple()

    return tuple(
        TargetPosition(symbol, side, target_notional * weight / total_weight, weight / total_weight)
        for symbol, weight in weights.items()
    )


def _rebalance_state(
    *,
    state: dict[str, Any],
    alert: TradingViewAlert,
    targets: tuple[TargetPosition, ...],
    prices: dict[str, float],
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    state = _mark_state(state, prices)
    realized = float(state.get("realized_pnl", 0.0))
    positions = {item["symbol"]: dict(item) for item in state.get("positions", [])}
    target_by_symbol = {target.symbol: target for target in targets}
    min_order = _env_float("PAPER_MIN_ORDER_NOTIONAL", 10.0)
    orders: list[dict[str, Any]] = []
    trades: list[dict[str, Any]] = list(state.get("trades", []))

    for symbol in sorted(set(positions) - set(target_by_symbol)):
        position = positions.pop(symbol)
        price = prices.get(symbol)
        if price is None:
            positions[symbol] = position
            continue
        realized += _position_unrealized(position, price)
        notional = _position_notional(position, price)
        if notional >= min_order:
            orders.append(_paper_order(symbol, _close_action(position["side"]), position["side"], notional, True, "close_removed_target"))
            trades.append(_trade_event(now, symbol, "CLOSE", position["side"], notional, price))

    for target in targets:
        price = prices.get(target.symbol)
        if price is None:
            continue

        current = positions.get(target.symbol)
        if current and current["side"] != target.side.value:
            realized += _position_unrealized(current, price)
            notional = _position_notional(current, price)
            if notional >= min_order:
                orders.append(_paper_order(target.symbol, _close_action(current["side"]), current["side"], notional, True, "close_opposite_side"))
                trades.append(_trade_event(now, target.symbol, "CLOSE", current["side"], notional, price))
            current = None
            positions.pop(target.symbol, None)

        if current is None:
            if target.notional >= min_order:
                quantity = target.notional / price
                positions[target.symbol] = _position(target.symbol, target.side.value, quantity, price)
                orders.append(_paper_order(target.symbol, _open_action(target.side.value), target.side.value, target.notional, False, "open_target"))
                trades.append(_trade_event(now, target.symbol, "OPEN", target.side.value, target.notional, price))
            continue

        current_notional = _position_notional(current, price)
        delta = target.notional - current_notional
        if abs(delta) < min_order:
            positions[target.symbol] = current
            continue

        if delta > 0:
            add_quantity = delta / price
            old_quantity = float(current["quantity"])
            new_quantity = old_quantity + add_quantity
            current["entry_price"] = (
                float(current["entry_price"]) * old_quantity + price * add_quantity
            ) / new_quantity
            current["quantity"] = new_quantity
            orders.append(_paper_order(target.symbol, _open_action(target.side.value), target.side.value, delta, False, "increase_target"))
            trades.append(_trade_event(now, target.symbol, "INCREASE", target.side.value, delta, price))
        else:
            reduce_notional = min(-delta, current_notional)
            reduce_quantity = reduce_notional / price
            fraction = min(1.0, reduce_quantity / float(current["quantity"]))
            realized += _position_unrealized(current, price) * fraction
            current["quantity"] = float(current["quantity"]) - reduce_quantity
            orders.append(_paper_order(target.symbol, _close_action(target.side.value), target.side.value, reduce_notional, True, "reduce_target"))
            trades.append(_trade_event(now, target.symbol, "REDUCE", target.side.value, reduce_notional, price))
            if float(current["quantity"]) <= 1e-12:
                positions.pop(target.symbol, None)
                continue

        positions[target.symbol] = current

    updated = {
        **state,
        "initial_equity": float(state.get("initial_equity", _initial_equity())),
        "realized_pnl": realized,
        "positions": list(positions.values()),
        "targets": [_target_payload(target) for target in targets],
        "orders": orders,
        "trades": trades[-_env_int("PAPER_TRADE_HISTORY_LIMIT", 500) :],
        "last_signal": _signal_payload(alert),
        "last_updated": now.isoformat(),
    }
    return _mark_state(updated, prices)


def _marked_equity(state: dict[str, Any], client: BinanceFuturesClient) -> float:
    symbols = {item["symbol"] for item in state.get("positions", [])}
    prices = _prices(client, symbols) if symbols else {}
    return float(_mark_state(state, prices)["equity"])


def _mark_state(state: dict[str, Any], prices: dict[str, float]) -> dict[str, Any]:
    initial = float(state.get("initial_equity", _initial_equity()))
    realized = float(state.get("realized_pnl", 0.0))
    positions = []
    unrealized = 0.0
    exposure = 0.0
    for raw in state.get("positions", []):
        position = dict(raw)
        price = prices.get(position["symbol"], position.get("last_price") or position.get("entry_price"))
        if price is None:
            continue
        position["last_price"] = float(price)
        position["notional"] = _position_notional(position, float(price))
        position["unrealized_pnl"] = _position_unrealized(position, float(price))
        unrealized += position["unrealized_pnl"]
        exposure += position["notional"]
        positions.append(position)

    equity = initial + realized + unrealized
    return {
        **state,
        "initial_equity": initial,
        "realized_pnl": realized,
        "unrealized_pnl": unrealized,
        "total_pnl": realized + unrealized,
        "equity": equity,
        "current_exposure": exposure,
        "positions": positions,
    }


def _state_payload(state: dict[str, Any]) -> dict[str, Any]:
    last_signal = state.get("last_signal") or {}
    target_exposure = sum(float(target.get("notional", 0.0)) for target in state.get("targets", []))
    equity = float(state.get("equity", _initial_equity()))
    total_pnl = float(state.get("total_pnl", 0.0))
    total_pnl_pct = total_pnl / float(state.get("initial_equity", _initial_equity())) * 100
    return {
        "enabled": True,
        "source": "Paper trading",
        "last_updated": state.get("last_updated"),
        "regime": last_signal.get("regime", "RANGE"),
        "market_bias": _signal_market_bias(str(last_signal.get("regime", "RANGE"))),
        "mode": _signal_mode(str(last_signal.get("regime", "RANGE"))),
        "equity": equity,
        "initial_equity": float(state.get("initial_equity", _initial_equity())),
        "realized_pnl": float(state.get("realized_pnl", 0.0)),
        "unrealized_pnl": float(state.get("unrealized_pnl", 0.0)),
        "total_pnl": total_pnl,
        "total_pnl_pct": total_pnl_pct,
        "current_exposure": float(state.get("current_exposure", 0.0)),
        "target_exposure": target_exposure,
        "leverage": float(state.get("current_exposure", 0.0)) / equity if equity > 0 else 0.0,
        "positions": [_position_payload(item) for item in state.get("positions", [])],
        "orders": list(state.get("orders", [])),
        "targets": list(state.get("targets", [])),
        "trades": list(reversed(state.get("trades", [])[-50:])),
        "latest_signal_id": last_signal.get("signal_id"),
        "events": _paper_events(state),
    }


def _paper_events(state: dict[str, Any]) -> list[dict[str, str]]:
    payload = _state_payload_without_events(state)
    events = [
        {
            "time": str(state.get("last_updated") or datetime.now(timezone.utc).isoformat()),
            "kind": "PAPER",
            "message": (
                f"Paper {payload['regime']} equity={payload['equity']:.2f} "
                f"PnL={payload['total_pnl']:+.2f} ({payload['total_pnl_pct']:+.2f}%) "
                f"exposure={payload['current_exposure']:.2f}"
            ),
        }
    ]
    for order in state.get("orders", [])[:12]:
        events.append(
            {
                "time": str(state.get("last_updated") or datetime.now(timezone.utc).isoformat()),
                "kind": "PAPER",
                "message": f"{order['symbol']} {order['action']} {order['side']} {order['notional']:.2f} {order['reason']}",
            }
        )
    return events


def _state_payload_without_events(state: dict[str, Any]) -> dict[str, Any]:
    last_signal = state.get("last_signal") or {}
    equity = float(state.get("equity", _initial_equity()))
    total_pnl = float(state.get("total_pnl", 0.0))
    initial = float(state.get("initial_equity", _initial_equity()))
    return {
        "regime": last_signal.get("regime", "RANGE"),
        "equity": equity,
        "total_pnl": total_pnl,
        "total_pnl_pct": total_pnl / initial * 100 if initial > 0 else 0.0,
        "current_exposure": float(state.get("current_exposure", 0.0)),
    }


def _prices(client: BinanceFuturesClient, symbols: set[str]) -> dict[str, float]:
    prices: dict[str, float] = {}
    for symbol in symbols:
        try:
            prices[symbol] = client.price(symbol)
        except Exception:
            continue
    return prices


def _position(symbol: str, side: str, quantity: float, entry_price: float) -> dict[str, Any]:
    return {
        "symbol": symbol,
        "side": side,
        "quantity": quantity,
        "entry_price": entry_price,
        "last_price": entry_price,
        "notional": quantity * entry_price,
        "unrealized_pnl": 0.0,
    }


def _position_notional(position: Mapping[str, Any], price: float) -> float:
    return abs(float(position["quantity"]) * price)


def _position_unrealized(position: Mapping[str, Any], price: float) -> float:
    quantity = float(position["quantity"])
    entry = float(position["entry_price"])
    if position["side"] == PositionSide.SHORT.value:
        return quantity * (entry - price)
    return quantity * (price - entry)


def _open_action(side: str) -> str:
    return OrderSide.BUY.value if side == PositionSide.LONG.value else OrderSide.SELL.value


def _close_action(side: str) -> str:
    return OrderSide.SELL.value if side == PositionSide.LONG.value else OrderSide.BUY.value


def _paper_order(
    symbol: str,
    action: str,
    side: str,
    notional: float,
    reduce_only: bool,
    reason: str,
) -> dict[str, Any]:
    return {
        "symbol": symbol,
        "action": action,
        "side": side,
        "notional": notional,
        "order_type": "MARKET",
        "reduce_only": reduce_only,
        "reason": reason,
    }


def _trade_event(
    now: datetime,
    symbol: str,
    action: str,
    side: str,
    notional: float,
    price: float,
) -> dict[str, Any]:
    return {
        "time": now.isoformat(),
        "symbol": symbol,
        "action": action,
        "side": side,
        "notional": notional,
        "price": price,
    }


def _position_payload(position: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "symbol": position["symbol"],
        "side": position["side"],
        "notional": float(position.get("notional", 0.0)),
        "entry_price": float(position.get("entry_price", 0.0)),
        "mark_price": float(position.get("last_price", 0.0)),
        "unrealized_pnl": float(position.get("unrealized_pnl", 0.0)),
    }


def _target_payload(target: TargetPosition) -> dict[str, Any]:
    return {
        "symbol": target.symbol,
        "side": target.side.value,
        "notional": target.notional,
        "weight": target.weight,
    }


def _signal_payload(alert: TradingViewAlert) -> dict[str, Any]:
    return {
        "regime": alert.regime.value,
        "target_leverage": alert.target_leverage,
        "tf": alert.tf,
        "time_ms": alert.time_ms,
        "bar_time_ms": alert.bar_time_ms,
        "signal_id": alert.dedupe_key(),
    }


def _signal_mode(regime: str) -> str:
    if regime in {TradingViewRegime.TOP10_LONG.value, TradingViewRegime.BTC_ETH_LONG.value}:
        return TradeMode.LONG.value
    if regime in {TradingViewRegime.ALT_WEAK_SHORT.value, TradingViewRegime.SHORT_MODE.value}:
        return TradeMode.SHORT.value
    if regime == TradingViewRegime.CHAOTIC.value:
        return TradeMode.PAUSED.value
    return TradeMode.NEUTRAL.value


def _signal_market_bias(regime: str) -> str:
    return {
        TradingViewRegime.TOP10_LONG.value: MarketBias.BROAD_BULL.value,
        TradingViewRegime.BTC_ETH_LONG.value: MarketBias.BTC_ONLY_BULL.value,
        TradingViewRegime.ALT_WEAK_SHORT.value: MarketBias.ALT_WEAK_BEAR.value,
        TradingViewRegime.SHORT_MODE.value: MarketBias.BROAD_BEAR.value,
        TradingViewRegime.CHAOTIC.value: MarketBias.CHAOTIC.value,
    }.get(regime, MarketBias.RANGE.value)


def _load_state(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"initial_equity": _initial_equity(), "realized_pnl": 0.0, "positions": [], "trades": []}
    return dict(data) if isinstance(data, dict) else {"initial_equity": _initial_equity(), "realized_pnl": 0.0, "positions": [], "trades": []}


def _write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(state, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
        temp_name = handle.name
    Path(temp_name).replace(path)


def _initial_equity() -> float:
    return _env_float("PAPER_INITIAL_EQUITY", _env_float("FALLBACK_EQUITY", 3300.0))


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default
