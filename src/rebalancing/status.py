from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .binance import BinanceCredentials, BinanceFuturesClient, live_trading_enabled
from .engine import RebalancingEngine
from .learning.params import active_engine_config
from .market_internals import MarketInternals, apply_market_cap_dominance, build_market_internals
from .models import (
    AccountSnapshot,
    BtcMarketSnapshot,
    EngineState,
    MarketCandidate,
    PlannedOrder,
    Position,
    RebalanceDecision,
)
from .paper import paper_status_payload
from .recording import record_decision, record_executions
from .signal_store import latest_tradingview_alert, tradingview_alert_events


@dataclass(frozen=True)
class RuntimeDecision:
    client: BinanceFuturesClient
    account: AccountSnapshot
    candidates: list[MarketCandidate]
    positions: list[Position]
    decision: RebalanceDecision
    internals: MarketInternals
    events: list[dict[str, str]]
    live_data: bool
    decision_record_id: int | None = None


def build_runtime_decision(*, force_rebalance: bool = False, record_mode: str | None = None) -> RuntimeDecision:
    now = datetime.now(timezone.utc)
    events: list[dict[str, str]] = []
    client = _binance_client(events)
    account = _account_snapshot(client, events)
    positions = _positions(client, events)
    candidates = _candidates(client, events)
    internals = build_market_internals(binance=client, candidates=candidates)
    candidates = apply_market_cap_dominance(candidates, internals)
    events.extend(_event("INTERNALS", message) for message in internals.messages[:20])
    btc = _btc_snapshot(client, events)

    decision = RebalancingEngine(active_engine_config()).evaluate(
        now=now,
        state=EngineState(),
        account=account,
        btc=btc,
        candidates=candidates,
        positions=positions,
        force_rebalance=force_rebalance,
    )

    decision_record_id = record_decision(
        decision,
        {
            "account": account,
            "positions": positions,
            "candidates": candidates,
            "btc": btc,
            "market_internals": internals,
        },
        mode=record_mode or ("live" if live_trading_enabled() else "paper"),
    )
    events.extend(_decision_events(decision))
    return RuntimeDecision(
        client=client,
        account=account,
        candidates=candidates,
        positions=positions,
        decision=decision,
        internals=internals,
        events=events,
        live_data=any(event["kind"] == "BINANCE" for event in events),
        decision_record_id=decision_record_id,
    )


def build_status_payload(*, force_rebalance: bool = False) -> dict[str, Any]:
    runtime = build_runtime_decision(force_rebalance=force_rebalance)
    return runtime_status_payload(runtime)


def runtime_status_payload(runtime: RuntimeDecision) -> dict[str, Any]:
    account = runtime.account
    decision = runtime.decision
    paper = paper_status_payload()
    current_exposure = (
        paper["current_exposure"] if paper else sum(position.notional for position in runtime.positions)
    )
    target_exposure = (
        paper["target_exposure"] if paper else sum(target.notional for target in decision.target_positions)
    )
    equity = paper["equity"] if paper else account.equity
    wallet_balance = paper["equity"] if paper else account.wallet_balance
    leverage = current_exposure / equity if equity > 0 else 0.0
    tv_signal = latest_tradingview_alert()
    paper_events = paper["events"] if paper else []
    events = _sorted_events(
        tradingview_alert_events(limit=_env_int("ENGINE_STATUS_ALERT_EVENT_LIMIT", 200)),
        paper_events,
        runtime.events,
    )

    return {
        "source": paper["source"] if paper else ("Binance live" if runtime.live_data else "Local fallback"),
        "last_updated": decision.now.isoformat(),
        "tradingview_signal": tv_signal,
        "paper": paper,
        "last_rebalance": paper["last_rebalance"] if paper else None,
        "regime": paper["regime"] if paper else decision.regime.value,
        "raw_regime": decision.raw_regime.value,
        "market_bias": paper["market_bias"] if paper else decision.market_bias.value,
        "mode": paper["mode"] if paper else decision.mode.value,
        "risk_state": decision.risk_action.value,
        "regime_score": decision.regime_score,
        "equity": equity,
        "wallet_balance": wallet_balance,
        "current_exposure": current_exposure,
        "target_exposure": target_exposure,
        "leverage": leverage,
        "daily_pnl_pct": paper["total_pnl_pct"] if paper else _pnl_pct(account.equity, account.day_start_equity),
        "weekly_pnl_pct": paper["total_pnl_pct"] if paper else _pnl_pct(account.equity, account.week_start_equity),
        "monthly_pnl_pct": paper["total_pnl_pct"] if paper else _pnl_pct(account.equity, account.month_start_equity),
        "cooldown_until": decision.next_state.cooldown_until.isoformat()
        if decision.next_state.cooldown_until
        else None,
        "live_trading_enabled": live_trading_enabled(),
        "market_internals": runtime.internals.to_payload(),
        "positions": paper["positions"] if paper else [_position_payload(position) for position in runtime.positions],
        "orders": paper["orders"] if paper else [_order_payload(order) for order in decision.orders],
        "targets": paper["targets"] if paper else [_target_payload(target) for target in decision.target_positions],
        "events": events,
        "watchlist": _watchlist_payload(runtime, paper=paper),
    }


def execute_runtime_orders(*, live: bool | None = None) -> dict[str, Any]:
    live = live if live is not None else live_trading_enabled()
    runtime = build_runtime_decision(force_rebalance=True, record_mode="live" if live else "paper")
    results = runtime.client.execute_planned_orders(runtime.decision.orders, live=live)
    record_executions(runtime.decision_record_id, results)
    payload = runtime_status_payload(runtime)
    payload["execution_results"] = [
        {
            "symbol": result.symbol,
            "side": result.side,
            "order_type": result.order_type,
            "quantity": result.quantity,
            "reduce_only": result.reduce_only,
            "live": result.live,
            "response": result.response,
        }
        for result in results
    ]
    return payload


def payload_to_json(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _binance_client(events: list[dict[str, str]]) -> BinanceFuturesClient:
    if os.environ.get("BINANCE_API_KEY") and os.environ.get("BINANCE_API_SECRET"):
        events.append(_event("BINANCE", "Signed Binance credentials loaded from environment"))
        return BinanceFuturesClient.from_env()

    events.append(_event("CONFIG", "BINANCE_API_KEY/BINANCE_API_SECRET missing; account uses local fallback"))
    return BinanceFuturesClient()


def _account_snapshot(client: BinanceFuturesClient, events: list[dict[str, str]]) -> AccountSnapshot:
    if client.credentials is None:
        return AccountSnapshot(
            equity=_env_float("FALLBACK_EQUITY", 1_000.0),
            wallet_balance=_env_float("FALLBACK_WALLET_BALANCE", 1_000.0),
            day_start_equity=_env_float("DAY_START_EQUITY", 1_000.0),
            week_start_equity=_env_float("WEEK_START_EQUITY", 1_000.0),
            month_start_equity=_env_float("MONTH_START_EQUITY", 1_000.0),
        )

    try:
        account = client.account()
        equity = float(account["totalMarginBalance"])
        wallet = float(account["totalWalletBalance"])
        return AccountSnapshot(
            equity=equity,
            wallet_balance=wallet,
            day_start_equity=_env_float("DAY_START_EQUITY", equity),
            week_start_equity=_env_float("WEEK_START_EQUITY", equity),
            month_start_equity=_env_float("MONTH_START_EQUITY", equity),
        )
    except Exception as exc:
        events.append(_event("ERROR", f"Binance account fetch failed: {exc}"))
        return AccountSnapshot(
            equity=_env_float("FALLBACK_EQUITY", 1_000.0),
            wallet_balance=_env_float("FALLBACK_WALLET_BALANCE", 1_000.0),
            day_start_equity=_env_float("DAY_START_EQUITY", 1_000.0),
            week_start_equity=_env_float("WEEK_START_EQUITY", 1_000.0),
            month_start_equity=_env_float("MONTH_START_EQUITY", 1_000.0),
        )


def _positions(client: BinanceFuturesClient, events: list[dict[str, str]]) -> list[Position]:
    if client.credentials is None:
        return []
    try:
        return client.positions()
    except Exception as exc:
        events.append(_event("ERROR", f"Binance positions fetch failed: {exc}"))
        return []


def _candidates(client: BinanceFuturesClient, events: list[dict[str, str]]) -> list[MarketCandidate]:
    try:
        candidates = client.market_candidates()
        events.append(_event("UNIVERSE", f"{len(candidates)} Binance USDT-M candidates loaded"))
        return candidates
    except Exception as exc:
        events.append(_event("ERROR", f"Binance universe fetch failed: {exc}"))
        return _fallback_candidates()


def _btc_snapshot(client: BinanceFuturesClient, events: list[dict[str, str]]) -> BtcMarketSnapshot:
    try:
        return client.btc_market_snapshot()
    except Exception as exc:
        events.append(_event("ERROR", f"BTC market snapshot failed: {exc}"))
        return BtcMarketSnapshot(
            close_1d=70_000,
            ema20_1d=68_000,
            ema60_1d=67_500,
            ema200_1d=60_000,
            ema20_4h=69_000,
            ema60_4h=68_500,
            adx_1d=12,
        )


def _fallback_candidates() -> list[MarketCandidate]:
    assets = ["BTC", "ETH", "BNB", "SOL", "XRP", "DOGE", "ADA", "AVAX", "LINK", "TRX"]
    total_volume = sum(range(len(assets), 0, -1))
    return [
        MarketCandidate(
            symbol=f"{asset}USDT",
            base_asset=asset,
            quote_volume_24h=(len(assets) - index) * 100_000_000,
            listed_days=1_000,
            dominance_rank=index + 1,
            dominance_pct=(len(assets) - index) / total_volume * 100,
            market_cap_rank=index + 1,
        )
        for index, asset in enumerate(assets)
    ]


def _watchlist_payload(runtime: RuntimeDecision, *, paper: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    decision = runtime.decision
    account = runtime.account
    tv_signal = latest_tradingview_alert()
    regime = paper["regime"] if paper else decision.regime.value
    mode = paper["mode"] if paper else decision.mode.value
    market_bias = paper["market_bias"] if paper else decision.market_bias.value
    equity = paper["equity"] if paper else account.equity
    current_exposure = paper["current_exposure"] if paper else sum(position.notional for position in runtime.positions)
    target_exposure = paper["target_exposure"] if paper else sum(target.notional for target in decision.target_positions)
    display_score = _tv_signal_score(tv_signal) if paper is not None and tv_signal is not None else decision.regime_score
    score_prefix = "TV Score" if paper is not None and tv_signal is not None else "Score"
    regime_meta = "Paper trading state" if paper else "Trading engine state"
    if paper is not None and tv_signal is not None:
        regime_meta = f"Paper trading state · Engine {decision.regime_score:.1f}"
    top10 = sorted(
        runtime.candidates,
        key=lambda candidate: (
            candidate.dominance_rank if candidate.dominance_rank is not None else 10_000,
            -(candidate.dominance_pct or 0.0),
            -candidate.quote_volume_24h,
        ),
    )[:10]

    rows = [
        {
            "symbol": "REGIME",
            "title": market_bias,
            "value": regime,
            "change": f"{score_prefix} {display_score:.1f}",
            "change_pct": mode,
            "color": _regime_color(regime),
            "marker": "R",
            "meta": regime_meta,
        },
        {
            "symbol": "INTERNALS",
            "title": runtime.internals.risk_label,
            "value": _fmt_pct(runtime.internals.volume_breadth_pct),
            "change": f"AD {_fmt_ratio(runtime.internals.advance_decline_ratio)}",
            "change_pct": f"{runtime.internals.advance_count}/{runtime.internals.decline_count}",
            "color": _internals_color(runtime.internals.risk_label),
            "marker": "I",
            "meta": f"{runtime.internals.source} breadth",
        },
        {
            "symbol": "STABLE.D",
            "title": "Stablecoin market-cap dominance",
            "value": _fmt_pct(runtime.internals.stable_dominance_pct),
            "change": "defensive" if (runtime.internals.stable_dominance_pct or 0) >= 10 else "normal",
            "change_pct": "cap",
            "color": "C08A17" if (runtime.internals.stable_dominance_pct or 0) >= 10 else "2F8F75",
            "marker": "S",
            "meta": "USDT/USDC/DAI/FDUSD/TUSD/USDE...",
        },
        {
            "symbol": "TOP10.D",
            "title": "Top10 non-stable market-cap dominance",
            "value": _fmt_pct(runtime.internals.top10_dominance_total_pct),
            "change": _fmt_pct(runtime.internals.top10_dominance_total2_pct),
            "change_pct": "vs TOTAL2",
            "color": "2563EB",
            "marker": "T",
            "meta": "CoinGecko market cap" if runtime.internals.source.startswith("coingecko") else "Binance volume fallback",
        },
        {
            "symbol": "EQUITY",
            "title": "USDT-M account",
            "value": f"{equity:.2f}",
            "change": f"Lev {current_exposure / equity:.2f}x" if equity > 0 else "Lev 0.00x",
            "change_pct": f"Target {target_exposure:.2f}",
            "color": "2563EB",
            "marker": "E",
            "meta": "Paper trading" if paper else ("Binance signed data" if runtime.live_data else "Fallback"),
        },
    ]

    if paper is not None:
        rows.insert(
            1,
            {
                "symbol": "PAPER.PNL",
                "title": "Virtual futures result",
                "value": f"{paper['total_pnl']:+.2f}",
                "change": f"{paper['total_pnl_pct']:+.2f}%",
                "change_pct": f"Realized {paper['realized_pnl']:+.2f}",
                "color": "2F8F75" if paper["total_pnl"] >= 0 else "C8404A",
                "marker": "P",
                "meta": f"Unrealized {paper['unrealized_pnl']:+.2f}",
            },
        )

    if tv_signal is not None:
        action = str(
            tv_signal.get("decision_action")
            or ("ENTER" if float(tv_signal.get("target_leverage") or 0) > 0 else "EXIT")
        )
        rows.insert(
            1,
            {
                "symbol": "TV.SIGNAL",
                "title": f"{tv_signal.get('regime', '-')} · tf {tv_signal.get('tf') or '-'}",
                "value": f"{float(tv_signal.get('target_leverage') or 0):.2f}x",
                "change": action.lower(),
                "change_pct": str(tv_signal.get("signal_id", "-"))[:16],
                "color": _regime_color(str(tv_signal.get("regime", "RANGE"))),
                "marker": "T",
                "meta": _tv_signal_reason(tv_signal),
            },
        )

    for candidate in top10:
        rows.append(
            {
                "symbol": candidate.symbol,
                "title": f"Dominance #{candidate.dominance_rank or '-'} · {candidate.base_asset}",
                "value": f"{candidate.dominance_pct or 0:.2f}%",
                "change": f"{candidate.change_24h_pct:+.2f}%",
                "change_pct": f"{candidate.quote_volume_24h / 1_000_000:.0f}M",
                "color": "2F8F75" if candidate.change_24h_pct >= 0 else "C8404A",
                "marker": candidate.base_asset[:1],
                "meta": f"Spread {candidate.spread_bps:.2f} bps",
            }
        )
    return rows


def _tv_signal_score(signal: dict[str, Any]) -> float:
    if signal.get("score") is not None:
        try:
            return float(signal["score"])
        except (TypeError, ValueError):
            pass

    score = 0.0
    score += _bool_pair_score(signal, "btc_up", "btc_down", 40.0)
    score += _bool_pair_score(signal, "total_up", "total_down", 25.0)
    score += _bool_pair_score(signal, "total2_up", "total2_down", 25.0)

    if _truthy(signal.get("btcd_down")):
        score += 10.0
    elif _truthy(signal.get("btcd_up")):
        score -= 10.0

    return score


def _tv_signal_reason(signal: dict[str, Any]) -> str:
    if signal.get("decision_reason"):
        return str(signal["decision_reason"])

    regime = str(signal.get("regime", "RANGE"))
    if regime != "RANGE":
        return "Server entry regime"

    btc_up = _truthy(signal.get("btc_up"))
    total_up = _truthy(signal.get("total_up"))
    total2_up = _truthy(signal.get("total2_up"))
    btcd_up = _truthy(signal.get("btcd_up"))
    btcd_down = _truthy(signal.get("btcd_down"))

    if btc_up and total_up and total2_up and btcd_up:
        return "BTC.D up reduces TOP10 leverage"
    if btc_up and total_up and total2_up and not btcd_down:
        return "TOP10 needs BTC.D confirmation"
    if btc_up and total_up and not total2_up and not btcd_up:
        return "BTC/ETH needs BTC.D up"
    if btc_up and total_up:
        return "mixed long filters"

    btc_down = _truthy(signal.get("btc_down"))
    total_down = _truthy(signal.get("total_down"))
    total2_down = _truthy(signal.get("total2_down"))
    total3_weak = _truthy(signal.get("total3_weak"))
    if btc_down and total_down and not total2_down:
        return "SHORT needs TOTAL2 down"
    if btc_down and total3_weak and not btcd_up:
        return "ALT short needs BTC.D up"

    return "Server range filters"


def _bool_pair_score(signal: dict[str, Any], up_key: str, down_key: str, weight: float) -> float:
    up = _truthy(signal.get(up_key))
    down = _truthy(signal.get(down_key))
    if up and not down:
        return weight
    if down and not up:
        return -weight
    return 0.0


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() == "true"
    return False


def _decision_events(decision: RebalanceDecision) -> list[dict[str, str]]:
    events = [_event("DECISION", reason) for reason in decision.reasons[:12]]
    if decision.orders:
        events.append(_event("ORDERS", f"{len(decision.orders)} planned orders generated"))
    else:
        events.append(_event("ORDERS", "No order needed for current state"))
    if live_trading_enabled():
        events.append(_event("LIVE", "Live Binance order execution is enabled"))
    else:
        events.append(_event("DRYRUN", "Order execution is dry-run unless both Binance live env flags are true"))
    return events


def _position_payload(position: Position) -> dict[str, Any]:
    return {
        "symbol": position.symbol,
        "side": position.side.value,
        "notional": position.notional,
        "entry_price": position.entry_price,
        "quantity": position.quantity,
        "mark_price": position.mark_price,
        "unrealized_pnl": position.unrealized_pnl,
        "liquidation_price": position.liquidation_price,
        "leverage": position.leverage,
        "margin_type": position.margin_type,
    }


def _order_payload(order: PlannedOrder) -> dict[str, Any]:
    return {
        "symbol": order.symbol,
        "action": order.side.value,
        "side": order.position_side.value,
        "notional": order.notional,
        "order_type": order.order_type.value,
        "reduce_only": order.reduce_only,
        "reason": order.reason,
    }


def _target_payload(target) -> dict[str, Any]:
    return {
        "symbol": target.symbol,
        "side": target.side.value,
        "notional": target.notional,
        "weight": target.weight,
    }


def _pnl_pct(equity: float, baseline: float) -> float:
    if baseline <= 0:
        return 0.0
    return (equity / baseline - 1.0) * 100


def _event(kind: str, message: str) -> dict[str, str]:
    return {
        "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "kind": kind,
        "message": message,
    }


def _sorted_events(*groups: list[dict[str, str]]) -> list[dict[str, str]]:
    events = [event for group in groups for event in group]
    return sorted(events, key=_event_sort_key, reverse=True)


def _event_sort_key(event: dict[str, str]) -> float:
    raw = str(event.get("time") or "")
    if raw.endswith("Z"):
        raw = f"{raw[:-1]}+00:00"
    try:
        return datetime.fromisoformat(raw).timestamp()
    except ValueError:
        return 0.0


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


def _regime_color(regime: str) -> str:
    if regime in {"BULL", "TOP10_LONG", "BTC_ETH_LONG"}:
        return "2F8F75"
    if regime in {"BEAR", "SHORT_MODE", "ALT_WEAK_SHORT"}:
        return "C8404A"
    if regime == "CHAOTIC":
        return "8F3FA8"
    return "787B86"


def _internals_color(label: str) -> str:
    if label == "BROAD_RISK_ON":
        return "2F8F75"
    if label in {"BROAD_RISK_OFF", "STABLE_DEFENSIVE"}:
        return "C8404A"
    return "787B86"


def _fmt_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.2f}%"


def _fmt_ratio(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.2f}"
