from __future__ import annotations

import unittest

from rebalancing.models import MarketCandidate, PositionSide
from rebalancing.portfolio import PortfolioBuilder


def candidates() -> list[MarketCandidate]:
    symbols = ["BTC", "ETH", "BNB", "SOL", "XRP", "DOGE", "ADA", "AVAX", "LINK", "MATIC"]
    return [
        MarketCandidate(
            symbol=f"{asset}USDT",
            base_asset=asset,
            quote_volume_24h=1_000_000_000 - index,
            listed_days=1_000,
            dominance_rank=index + 1,
            dominance_pct=50.0 - index,
            market_cap_rank=index + 1,
        )
        for index, asset in enumerate(symbols)
    ]


class PortfolioBuilderTest(unittest.TestCase):
    def test_bull_targets_use_btc_eth_core_weights(self) -> None:
        builder = PortfolioBuilder()

        targets = builder.build_long_targets(equity=1_000, candidates=candidates(), leverage=2.0)
        by_symbol = {target.symbol: target for target in targets}

        self.assertEqual(len(targets), 10)
        self.assertEqual(by_symbol["BTCUSDT"].side, PositionSide.LONG)
        self.assertAlmostEqual(by_symbol["BTCUSDT"].notional, 500)
        self.assertAlmostEqual(by_symbol["ETHUSDT"].notional, 400)
        self.assertAlmostEqual(by_symbol["BNBUSDT"].notional, 137.5)

    def test_long_universe_uses_top_dominance_and_excludes_stables(self) -> None:
        builder = PortfolioBuilder()
        raw = [
            MarketCandidate(
                symbol="USDCUSDT",
                base_asset="USDC",
                quote_volume_24h=9_000_000_000,
                listed_days=1_000,
                dominance_rank=1,
                dominance_pct=10,
            ),
            MarketCandidate(
                symbol="DAIUSDT",
                base_asset="DAI",
                quote_volume_24h=8_000_000_000,
                listed_days=1_000,
                dominance_rank=2,
                dominance_pct=9,
            ),
        ]
        raw.extend(candidates())

        universe = builder.select_long_universe(raw)

        self.assertEqual(len(universe), 10)
        self.assertNotIn("USDCUSDT", {candidate.symbol for candidate in universe})
        self.assertNotIn("DAIUSDT", {candidate.symbol for candidate in universe})
        self.assertEqual(universe[0].symbol, "BTCUSDT")

    def test_long_universe_does_not_fill_market_cap_basket_with_unmatched_symbols(self) -> None:
        builder = PortfolioBuilder()
        raw = [
            MarketCandidate(
                symbol="BTCUSDT",
                base_asset="BTC",
                quote_volume_24h=1_000_000_000,
                listed_days=1_000,
                dominance_rank=1,
                dominance_pct=50,
                market_cap_rank=1,
            ),
            MarketCandidate(
                symbol="ETHUSDT",
                base_asset="ETH",
                quote_volume_24h=900_000_000,
                listed_days=1_000,
                dominance_rank=2,
                dominance_pct=10,
                market_cap_rank=2,
            ),
            MarketCandidate(
                symbol="BSBUSDT",
                base_asset="BSB",
                quote_volume_24h=2_000_000_000,
                listed_days=90,
                dominance_rank=10001,
                dominance_pct=5,
                market_cap_rank=None,
            ),
        ]

        universe = builder.select_long_universe(raw)

        self.assertEqual({candidate.symbol for candidate in universe}, {"BTCUSDT", "ETHUSDT"})


if __name__ == "__main__":
    unittest.main()
