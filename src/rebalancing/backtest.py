from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timedelta, timezone
from typing import Any

from .engine import RebalancingEngine
from .models import AccountSnapshot, BtcMarketSnapshot, EngineState, MarketCandidate, Position, PositionSide, Regime, TradeMode


def run_reinforced_tests(*, iterations: int = 500, seed: int = 1214) -> dict[str, Any]:
    random.seed(seed)
    engine = RebalancingEngine()
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    state = EngineState()
    failures: list[str] = []
    max_target_leverage = 0.0
    decisions = {"BULL": 0, "BEAR": 0, "RANGE": 0, "CHAOTIC": 0}

    for index in range(iterations):
        equity = random.uniform(500, 10_000)
        account = AccountSnapshot(
            equity=equity,
            wallet_balance=equity,
            day_start_equity=equity / random.uniform(0.98, 1.02),
            week_start_equity=equity / random.uniform(0.94, 1.04),
            month_start_equity=equity / random.uniform(0.88, 1.08),
        )
        btc = _random_btc_snapshot()
        positions = _random_positions(equity)
        decision = engine.evaluate(
            now=now + timedelta(hours=4 * index),
            state=state,
            account=account,
            btc=btc,
            candidates=_candidates(),
            positions=positions,
        )

        target_exposure = sum(target.notional for target in decision.target_positions)
        target_leverage = target_exposure / equity
        max_target_leverage = max(max_target_leverage, target_leverage)
        decisions[decision.regime.value] += 1

        if target_leverage > 2.000001:
            failures.append(f"target leverage exceeded max at iteration {index}: {target_leverage:.4f}")

        if state.mode == TradeMode.LONG and decision.mode == TradeMode.SHORT:
            failures.append(f"direct LONG->SHORT transition at iteration {index}")
        if state.mode == TradeMode.SHORT and decision.mode == TradeMode.LONG:
            failures.append(f"direct SHORT->LONG transition at iteration {index}")

        state = decision.next_state

    return {
        "ok": not failures,
        "iterations": iterations,
        "seed": seed,
        "max_target_leverage": round(max_target_leverage, 6),
        "decisions": decisions,
        "failures": failures[:20],
    }


def run_fixed_scenarios() -> dict[str, Any]:
    engine = RebalancingEngine()
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    account = AccountSnapshot(
        equity=1_000,
        wallet_balance=1_000,
        day_start_equity=1_000,
        week_start_equity=1_000,
        month_start_equity=1_000,
    )

    scenarios = {
        "bull": _btc_snapshot("bull"),
        "bear": _btc_snapshot("bear"),
        "range": _btc_snapshot("range"),
        "chaotic": _btc_snapshot("chaotic"),
    }
    results: dict[str, Any] = {}
    for name, btc in scenarios.items():
        decision = engine.evaluate(
            now=now,
            state=EngineState(raw_regime_history=(Regime.BULL, Regime.BULL) if name == "bull" else tuple()),
            account=account,
            btc=btc,
            candidates=_candidates(),
            positions=[],
        )
        results[name] = {
            "regime": decision.regime.value,
            "raw_regime": decision.raw_regime.value,
            "mode": decision.mode.value,
            "target_exposure": round(sum(target.notional for target in decision.target_positions), 2),
            "orders": len(decision.orders),
        }
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Run deterministic and reinforced engine tests.")
    parser.add_argument("--iterations", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1214)
    args = parser.parse_args()

    payload = {
        "fixed_scenarios": run_fixed_scenarios(),
        "reinforced": run_reinforced_tests(iterations=args.iterations, seed=args.seed),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def _random_btc_snapshot() -> BtcMarketSnapshot:
    kind = random.choice(("bull", "bear", "range", "chaotic"))
    return _btc_snapshot(kind)


def _btc_snapshot(kind: str) -> BtcMarketSnapshot:
    if kind == "bull":
        return BtcMarketSnapshot(
            close_1d=70_000,
            ema20_1d=68_000,
            ema60_1d=64_000,
            ema200_1d=55_000,
            ema20_4h=70_500,
            ema60_4h=69_000,
            adx_1d=24,
        )
    if kind == "bear":
        return BtcMarketSnapshot(
            close_1d=50_000,
            ema20_1d=52_000,
            ema60_1d=56_000,
            ema200_1d=60_000,
            ema20_4h=49_000,
            ema60_4h=51_000,
            adx_1d=25,
        )
    if kind == "chaotic":
        return BtcMarketSnapshot(
            close_1d=60_000,
            ema20_1d=60_500,
            ema60_1d=60_000,
            ema200_1d=58_000,
            ema20_4h=59_000,
            ema60_4h=60_500,
            adx_1d=16,
            change_4h_pct=8.0,
        )
    return BtcMarketSnapshot(
        close_1d=60_000,
        ema20_1d=60_100,
        ema60_1d=60_000,
        ema200_1d=59_500,
        ema20_4h=60_050,
        ema60_4h=60_100,
        adx_1d=12,
    )


def _candidates() -> list[MarketCandidate]:
    assets = ["BTC", "ETH", "BNB", "SOL", "XRP", "DOGE", "ADA", "AVAX", "LINK", "TRX"]
    return [
        MarketCandidate(
            symbol=f"{asset}USDT",
            base_asset=asset,
            quote_volume_24h=(len(assets) - index) * 1_000_000_000,
            listed_days=1_000,
            dominance_rank=index + 1,
            dominance_pct=10 - index,
            market_cap_rank=index + 1,
        )
        for index, asset in enumerate(assets)
    ]


def _random_positions(equity: float) -> list[Position]:
    if random.random() < 0.55:
        return []
    side = random.choice((PositionSide.LONG, PositionSide.SHORT))
    notional = random.uniform(20, equity * 0.75)
    return [Position(symbol=random.choice(("BTCUSDT", "ETHUSDT", "SOLUSDT")), side=side, notional=notional)]


if __name__ == "__main__":
    main()
