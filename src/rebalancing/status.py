from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .binance import BinanceCredentials, BinanceFuturesClient, live_trading_enabled
from .engine import RebalancingEngine
from .models import (
    AccountSnapshot,
    BtcMarketSnapshot,
    EngineState,
    MarketCandidate,
    PlannedOrder,
    Position,
    RebalanceDecision,
)


@dataclass(frozen=True)
class RuntimeDecision:
    client: BinanceFuturesClient
    account: AccountSnapshot
    candidates: list[MarketCandidate]
    positions: list[Position]
    decision: RebalanceDecision
    events: list[dict[str, str]]
    live_data: bool


def build_runtime_decision(*, force_rebalance: bool = False) -> RuntimeDecision:
    now = datetime.now(timezone.utc)
    events: list[dict[str, str]] = []
    client = _binance_client(events)
    account = _account_snapshot(client, events)
    positions = _positions(client, events)
    candidates = _candidates(client, events)
    btc = _btc_snapshot(client, events)

    decision = RebalancingEngine().evaluate(
        now=now,
        state=EngineState(),
        account=account,
        btc=btc,
        candidates=candidates,
        positions=positions,
        force_rebalance=force_rebalance,
    )

    events.extend(_decision_events(decision))
    return RuntimeDecision(
        client=client,
        account=account,
        candidates=candidates,
        positions=positions,
        decision=decision,
        events=events,
        live_data=any(event["kind"] == "BINANCE" for event in events),
    )


def build_status_payload(*, force_rebalance: bool = False) -> dict[str, Any]:
    runtime = build_runtime_decision(force_rebalance=force_rebalance)
    return runtime_status_payload(runtime)


def runtime_status_payload(runtime: RuntimeDecision) -> dict[str, Any]:
    account = runtime.account
    decision = runtime.decision
    current_exposure = sum(position.notional for position in runtime.positions)
    target_exposure = sum(target.notional for target in decision.target_positions)
    leverage = current_exposure / account.equity if account.equity > 0 else 0.0

    return {
        "source": "Binance live" if runtime.live_data else "Local fallback",
        "last_updated": decision.now.isoformat(),
        "regime": decision.regime.value,
        "raw_regime": decision.raw_regime.value,
        "market_bias": decision.market_bias.value,
        "mode": decision.mode.value,
        "risk_state": decision.risk_action.value,
        "regime_score": decision.regime_score,
        "equity": account.equity,
        "wallet_balance": account.wallet_balance,
        "current_exposure": current_exposure,
        "target_exposure": target_exposure,
        "leverage": leverage,
        "daily_pnl_pct": _pnl_pct(account.equity, account.day_start_equity),
        "weekly_pnl_pct": _pnl_pct(account.equity, account.week_start_equity),
        "monthly_pnl_pct": _pnl_pct(account.equity, account.month_start_equity),
        "cooldown_until": decision.next_state.cooldown_until.isoformat()
        if decision.next_state.cooldown_until
        else None,
        "live_trading_enabled": live_trading_enabled(),
        "positions": [_position_payload(position) for position in runtime.positions],
        "orders": [_order_payload(order) for order in decision.orders],
        "targets": [_target_payload(target) for target in decision.target_positions],
        "events": runtime.events,
        "watchlist": _watchlist_payload(runtime),
    }


def execute_runtime_orders(*, live: bool | None = None) -> dict[str, Any]:
    runtime = build_runtime_decision(force_rebalance=True)
    live = live if live is not None else live_trading_enabled()
    results = runtime.client.execute_planned_orders(runtime.decision.orders, live=live)
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


def _watchlist_payload(runtime: RuntimeDecision) -> list[dict[str, Any]]:
    decision = runtime.decision
    account = runtime.account
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
            "title": decision.market_bias.value,
            "value": decision.regime.value,
            "change": f"Score {decision.regime_score:.1f}",
            "change_pct": decision.mode.value,
            "color": _regime_color(decision.regime.value),
            "marker": "R",
            "meta": "Trading engine state",
        },
        {
            "symbol": "EQUITY",
            "title": "USDT-M account",
            "value": f"{account.equity:.2f}",
            "change": f"Lev {sum(position.notional for position in runtime.positions) / account.equity:.2f}x",
            "change_pct": f"Target {sum(target.notional for target in decision.target_positions):.2f}",
            "color": "2563EB",
            "marker": "E",
            "meta": "Binance signed data" if runtime.live_data else "Fallback",
        },
    ]

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


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


def _regime_color(regime: str) -> str:
    if regime in {"BULL", "TOP10_LONG"}:
        return "2F8F75"
    if regime in {"BEAR", "SHORT_MODE", "ALT_WEAK_SHORT"}:
        return "C8404A"
    if regime == "CHAOTIC":
        return "8F3FA8"
    return "787B86"
