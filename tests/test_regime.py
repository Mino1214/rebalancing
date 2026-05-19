from __future__ import annotations

import unittest
from dataclasses import replace

from rebalancing.models import BtcMarketSnapshot, CryptoMarketSnapshot, EngineState, MarketBias, MarketIndexSnapshot, Regime
from rebalancing.regime import RegimeDetector


def bull_snapshot() -> BtcMarketSnapshot:
    return BtcMarketSnapshot(
        close_1d=70_000,
        ema20_1d=68_000,
        ema60_1d=65_000,
        ema200_1d=50_000,
        ema20_4h=70_500,
        ema60_4h=69_000,
        adx_1d=24,
    )


def bear_snapshot() -> BtcMarketSnapshot:
    return BtcMarketSnapshot(
        close_1d=40_000,
        ema20_1d=42_000,
        ema60_1d=45_000,
        ema200_1d=50_000,
        ema20_4h=39_000,
        ema60_4h=41_000,
        adx_1d=24,
    )


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


class RegimeDetectorTest(unittest.TestCase):
    def test_bull_requires_three_persisted_signals(self) -> None:
        detector = RegimeDetector()
        state = EngineState()

        first = detector.detect(bull_snapshot(), state)
        self.assertEqual(first.raw, Regime.BULL)
        self.assertEqual(first.confirmed, Regime.RANGE)

        state = replace(state, raw_regime_history=first.history, last_confirmed_regime=first.confirmed)
        second = detector.detect(bull_snapshot(), state)
        self.assertEqual(second.confirmed, Regime.RANGE)

        state = replace(state, raw_regime_history=second.history, last_confirmed_regime=second.confirmed)
        third = detector.detect(bull_snapshot(), state)
        self.assertEqual(third.confirmed, Regime.BULL)

    def test_chaotic_is_immediate(self) -> None:
        detector = RegimeDetector()
        snapshot = replace(bull_snapshot(), change_4h_pct=7.5)

        result = detector.detect(snapshot, EngineState())

        self.assertEqual(result.raw, Regime.CHAOTIC)
        self.assertEqual(result.confirmed, Regime.CHAOTIC)

    def test_broad_bull_uses_btc_total_alts_and_dominance(self) -> None:
        detector = RegimeDetector()
        market = CryptoMarketSnapshot(
            btc=bull_snapshot(),
            total=index_snapshot("TOTAL", "up"),
            total2=index_snapshot("TOTAL2", "up"),
            total3=index_snapshot("TOTAL3", "up"),
            btc_dominance=index_snapshot("BTC.D", "down"),
        )

        raw, bias, score, _ = detector.raw_signal(market)

        self.assertEqual(raw, Regime.BULL)
        self.assertEqual(bias, MarketBias.BROAD_BULL)
        self.assertEqual(score, 100)

    def test_btc_only_bull_is_bull_with_reduced_alt_bias(self) -> None:
        detector = RegimeDetector()
        market = CryptoMarketSnapshot(
            btc=bull_snapshot(),
            total=index_snapshot("TOTAL", "up"),
            total2=index_snapshot("TOTAL2", "down"),
            total3=index_snapshot("TOTAL3", "down"),
            btc_dominance=index_snapshot("BTC.D", "up"),
        )

        raw, bias, score, _ = detector.raw_signal(market)

        self.assertEqual(raw, Regime.BULL)
        self.assertEqual(bias, MarketBias.BTC_ONLY_BULL)
        self.assertEqual(score, 30)

    def test_alt_weak_bear_is_distinguished_from_broad_bear(self) -> None:
        detector = RegimeDetector()
        market = CryptoMarketSnapshot(
            btc=bear_snapshot(),
            total=index_snapshot("TOTAL", "down"),
            total2=index_snapshot("TOTAL2", "down"),
            total3=index_snapshot("TOTAL3", "down"),
            btc_dominance=index_snapshot("BTC.D", "up"),
        )

        raw, bias, score, _ = detector.raw_signal(market)

        self.assertEqual(raw, Regime.BEAR)
        self.assertEqual(bias, MarketBias.ALT_WEAK_BEAR)
        self.assertEqual(score, -100)


if __name__ == "__main__":
    unittest.main()
