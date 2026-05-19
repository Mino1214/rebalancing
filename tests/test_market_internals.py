from __future__ import annotations

import os
import unittest
from datetime import datetime, timezone

from rebalancing.market_internals import (
    MarketCapCoin,
    MarketInternals,
    advance_decline_from_candidates,
    apply_market_cap_dominance,
    build_market_internals,
)
from rebalancing.models import Candle, MarketCandidate


def candidate(symbol: str, change: float, volume: float = 1_000_000_000) -> MarketCandidate:
    base = symbol.removesuffix("USDT")
    return MarketCandidate(
        symbol=symbol,
        base_asset=base,
        quote_volume_24h=volume,
        listed_days=1_000,
        change_24h_pct=change,
        dominance_rank=100,
        dominance_pct=0.1,
        stablecoin=base in {"USDT", "USDC", "DAI"},
    )


class FakeCoinGeckoClient:
    def global_data(self):
        return {"data": {"total_market_cap": {"usd": 1_000_000}}}

    def coins_markets(self, *, ids=None, order="market_cap_desc", per_page=250, page=1):
        if ids:
            return [
                {"id": "tether", "symbol": "usdt", "name": "Tether", "market_cap": 60_000, "market_cap_rank": 3},
                {"id": "usd-coin", "symbol": "usdc", "name": "USDC", "market_cap": 40_000, "market_cap_rank": 5},
            ]
        return [
            {"id": "bitcoin", "symbol": "btc", "name": "Bitcoin", "market_cap": 500_000, "market_cap_rank": 1},
            {"id": "ethereum", "symbol": "eth", "name": "Ethereum", "market_cap": 200_000, "market_cap_rank": 2},
            {"id": "tether", "symbol": "usdt", "name": "Tether", "market_cap": 60_000, "market_cap_rank": 3},
            {"id": "solana", "symbol": "sol", "name": "Solana", "market_cap": 50_000, "market_cap_rank": 4},
            {"id": "xrp", "symbol": "xrp", "name": "XRP", "market_cap": 40_000, "market_cap_rank": 6},
            {"id": "cardano", "symbol": "ada", "name": "Cardano", "market_cap": 30_000, "market_cap_rank": 7},
            {"id": "dogecoin", "symbol": "doge", "name": "Dogecoin", "market_cap": 20_000, "market_cap_rank": 8},
            {"id": "chainlink", "symbol": "link", "name": "Chainlink", "market_cap": 10_000, "market_cap_rank": 9},
        ]


class FakeBinanceClient:
    def klines(self, symbol: str, interval: str, *, limit: int = 21):
        volumes = [100 + index for index in range(20)] + [200]
        return [
            Candle(
                timestamp=datetime(2026, 1, min(index + 1, 28), tzinfo=timezone.utc),
                open=1,
                high=1,
                low=1,
                close=1,
                volume=float(volume),
            )
            for index, volume in enumerate(volumes)
        ]


class MarketInternalsTest(unittest.TestCase):
    def setUp(self) -> None:
        import rebalancing.market_internals as module

        module._CACHE = None
        os.environ["MARKET_INTERNALS_CACHE_SECONDS"] = "0"

    def test_advance_decline_excludes_stables(self) -> None:
        advance, decline, flat, ratio = advance_decline_from_candidates(
            [
                candidate("BTCUSDT", 1.0),
                candidate("ETHUSDT", -1.0),
                candidate("SOLUSDT", 0.0),
                candidate("USDCUSDT", 5.0),
            ]
        )

        self.assertEqual(advance, 1)
        self.assertEqual(decline, 1)
        self.assertEqual(flat, 1)
        self.assertEqual(ratio, 1.0)

    def test_market_cap_dominance_rewrites_candidate_rank(self) -> None:
        internals = MarketInternals(
            source="coingecko",
            total_market_cap_usd=1_000_000,
            top10_market_cap_coins=(
                MarketCapCoin("bitcoin", "BTC", "Bitcoin", 500_000, 1, 0),
                MarketCapCoin("solana", "SOL", "Solana", 50_000, 4, 0),
            ),
        )

        updated = apply_market_cap_dominance(
            [
                candidate("SOLUSDT", 1, volume=10),
                candidate("BTCUSDT", 1, volume=1),
                candidate("DOGEUSDT", 1, volume=100),
            ],
            internals,
        )
        by_symbol = {item.symbol: item for item in updated}

        self.assertEqual(by_symbol["BTCUSDT"].dominance_rank, 1)
        self.assertEqual(by_symbol["SOLUSDT"].dominance_rank, 2)
        self.assertGreater(by_symbol["DOGEUSDT"].dominance_rank or 0, 10_000)

    def test_build_market_internals_combines_coingecko_and_binance(self) -> None:
        internals = build_market_internals(
            binance=FakeBinanceClient(),  # type: ignore[arg-type]
            coingecko=FakeCoinGeckoClient(),  # type: ignore[arg-type]
            candidates=[
                candidate("BTCUSDT", 1, volume=100),
                candidate("ETHUSDT", -1, volume=90),
                candidate("SOLUSDT", 2, volume=80),
            ],
        )

        self.assertEqual(internals.source, "coingecko+binance")
        self.assertAlmostEqual(internals.stable_dominance_pct or 0, 10.0)
        self.assertEqual(internals.volume_breadth_count, 3)
        self.assertEqual(internals.volume_breadth_total, 3)
        self.assertEqual(internals.advance_count, 2)
        self.assertEqual(internals.decline_count, 1)


if __name__ == "__main__":
    unittest.main()
