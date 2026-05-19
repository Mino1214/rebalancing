from __future__ import annotations

import unittest
from datetime import datetime, timezone

from rebalancing import (
    AccountSnapshot,
    BtcMarketSnapshot,
    CryptoMarketSnapshot,
    EngineState,
    MarketIndexSnapshot,
    MarketCandidate,
    MarketBias,
    Position,
    PositionSide,
    RebalancingEngine,
    Regime,
    TradeMode,
)


def btc_bull() -> BtcMarketSnapshot:
    return BtcMarketSnapshot(
        close_1d=70_000,
        ema20_1d=68_000,
        ema60_1d=65_000,
        ema200_1d=50_000,
        ema20_4h=70_500,
        ema60_4h=69_000,
        adx_1d=24,
    )


def market_candidates() -> list[MarketCandidate]:
    assets = ["BTC", "ETH", "BNB", "SOL", "XRP", "DOGE", "ADA", "AVAX", "LINK", "MATIC"]
    return [
        MarketCandidate(
            symbol=f"{asset}USDT",
            base_asset=asset,
            quote_volume_24h=1_000_000_000,
            listed_days=1_000,
            market_cap_rank=index + 1,
        )
        for index, asset in enumerate(assets)
    ]


def index_snapshot(name: str, direction: str) -> MarketIndexSnapshot:
    if direction == "up":
        return MarketIndexSnapshot(
            name=name,
            close_1d=120,
            ema20_1d=115,
            ema60_1d=100,
            ema200_1d=90,
            ema20_4h=122,
            ema60_4h=116,
            adx_1d=22,
        )
    return MarketIndexSnapshot(
        name=name,
        close_1d=80,
        ema20_1d=85,
        ema60_1d=100,
        ema200_1d=110,
        ema20_4h=78,
        ema60_4h=84,
        adx_1d=22,
    )


class EngineTest(unittest.TestCase):
    def test_deposit_waits_for_next_candle_before_new_entries(self) -> None:
        now = datetime(2026, 1, 1, 9, 15, tzinfo=timezone.utc)
        engine = RebalancingEngine()
        state = EngineState(
            mode=TradeMode.LONG,
            raw_regime_history=(Regime.BULL, Regime.BULL),
            last_confirmed_regime=Regime.BULL,
            last_wallet_balance=1_000,
            last_rebalance_at=now,
        )

        decision = engine.evaluate(
            now=now,
            state=state,
            account=AccountSnapshot(
                equity=1_500,
                wallet_balance=1_500,
                day_start_equity=1_500,
                week_start_equity=1_500,
                month_start_equity=1_500,
            ),
            btc=btc_bull(),
            candidates=market_candidates(),
            positions=[
                Position("BTCUSDT", PositionSide.LONG, 500),
                Position("ETHUSDT", PositionSide.LONG, 400),
                Position("BNBUSDT", PositionSide.LONG, 137.5),
            ],
        )

        self.assertEqual(decision.regime, Regime.BULL)
        self.assertIsNotNone(decision.next_state.pending_deposit_rebalance_at)
        self.assertEqual(decision.orders, tuple())

    def test_btc_only_bull_targets_btc_eth_not_top_10(self) -> None:
        now = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
        engine = RebalancingEngine()
        market = CryptoMarketSnapshot(
            btc=btc_bull(),
            total=index_snapshot("TOTAL", "up"),
            total2=index_snapshot("TOTAL2", "down"),
            total3=index_snapshot("TOTAL3", "down"),
            btc_dominance=index_snapshot("BTC.D", "up"),
        )

        decision = engine.evaluate(
            now=now,
            state=EngineState(raw_regime_history=(Regime.BULL, Regime.BULL)),
            account=AccountSnapshot(
                equity=1_000,
                wallet_balance=1_000,
                day_start_equity=1_000,
                week_start_equity=1_000,
                month_start_equity=1_000,
            ),
            market=market,
            candidates=market_candidates(),
            positions=[],
        )

        self.assertEqual(decision.regime, Regime.BULL)
        self.assertEqual(decision.market_bias, MarketBias.BTC_ONLY_BULL)
        self.assertEqual({target.symbol for target in decision.target_positions}, {"BTCUSDT", "ETHUSDT"})
        self.assertAlmostEqual(sum(target.notional for target in decision.target_positions), 1_000)


if __name__ == "__main__":
    unittest.main()
