from __future__ import annotations

import unittest
from datetime import datetime, timezone

from rebalancing.binance import BinanceFuturesClient
from rebalancing.models import PositionSide


class BinanceFuturesClientTest(unittest.TestCase):
    def test_position_parser_maps_one_way_short(self) -> None:
        position = BinanceFuturesClient._position_from_account_position(
            {
                "symbol": "BTCUSDT",
                "positionSide": "BOTH",
                "positionAmt": "-0.10",
                "notional": "-7000",
                "entryPrice": "70000",
                "markPrice": "69000",
                "unRealizedProfit": "100",
                "liquidationPrice": "82000",
                "leverage": "2",
                "marginType": "cross",
            }
        )

        self.assertIsNotNone(position)
        self.assertEqual(position.side, PositionSide.SHORT)
        self.assertEqual(position.notional, 7000)
        self.assertEqual(position.quantity, 0.1)
        self.assertEqual(position.entry_price, 70000)
        self.assertEqual(position.mark_price, 69000)
        self.assertEqual(position.unrealized_pnl, 100)
        self.assertEqual(position.liquidation_price, 82000)
        self.assertEqual(position.leverage, 2)
        self.assertEqual(position.margin_type, "cross")

    def test_market_candidate_parser_filters_to_trading_usdt_perps(self) -> None:
        candidate = BinanceFuturesClient._market_candidate_from_raw(
            {
                "symbol": "BTCUSDT",
                "contractType": "PERPETUAL",
                "status": "TRADING",
                "baseAsset": "BTC",
                "quoteAsset": "USDT",
                "onboardDate": 1577836800000,
            },
            {"quoteVolume": "1000000000", "priceChangePercent": "3.5"},
            datetime(2026, 1, 1, tzinfo=timezone.utc),
        )

        self.assertIsNotNone(candidate)
        self.assertEqual(candidate.symbol, "BTCUSDT")
        self.assertEqual(candidate.quote_volume_24h, 1_000_000_000)
        self.assertEqual(candidate.change_24h_pct, 3.5)
        self.assertGreater(candidate.listed_days, 2_000)


if __name__ == "__main__":
    unittest.main()
