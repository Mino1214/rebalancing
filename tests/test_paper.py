from __future__ import annotations

import unittest

from rebalancing.models import PositionSide, TargetPosition
from rebalancing.paper import _mark_state, _rebalance_state
from rebalancing.tradingview import TradingViewAlert


class PaperTradingTest(unittest.TestCase):
    def test_open_marks_and_closes_long_position(self) -> None:
        alert = _alert("TOP10_LONG", 1.0)
        opened = _rebalance_state(
            state={"initial_equity": 1_000.0, "realized_pnl": 0.0, "positions": [], "trades": []},
            alert=alert,
            targets=(TargetPosition("BTCUSDT", PositionSide.LONG, 100.0, 1.0),),
            prices={"BTCUSDT": 100.0},
        )
        marked = _mark_state(opened, {"BTCUSDT": 110.0})

        self.assertEqual(len(marked["positions"]), 1)
        self.assertAlmostEqual(marked["unrealized_pnl"], 10.0)
        self.assertAlmostEqual(marked["equity"], 1_010.0)

        closed = _rebalance_state(
            state=marked,
            alert=_alert("RANGE", 0.0),
            targets=tuple(),
            prices={"BTCUSDT": 110.0},
        )

        self.assertEqual(closed["positions"], [])
        self.assertAlmostEqual(closed["realized_pnl"], 10.0)
        self.assertAlmostEqual(closed["equity"], 1_010.0)

    def test_short_position_profits_when_price_falls(self) -> None:
        opened = _rebalance_state(
            state={"initial_equity": 1_000.0, "realized_pnl": 0.0, "positions": [], "trades": []},
            alert=_alert("SHORT_MODE", 1.0),
            targets=(TargetPosition("BTCUSDT", PositionSide.SHORT, 100.0, 1.0),),
            prices={"BTCUSDT": 100.0},
        )
        marked = _mark_state(opened, {"BTCUSDT": 90.0})

        self.assertAlmostEqual(marked["unrealized_pnl"], 10.0)
        self.assertAlmostEqual(marked["equity"], 1_010.0)


def _alert(regime: str, leverage: float) -> TradingViewAlert:
    return TradingViewAlert.parse(
        {
            "schema": "crypto_regime_v1",
            "source": "tradingview",
            "regime": regime,
            "target_leverage": leverage,
            "btc_up": regime == "TOP10_LONG",
            "btc_down": regime == "SHORT_MODE",
            "total_up": regime == "TOP10_LONG",
            "total_down": regime == "SHORT_MODE",
            "total2_up": regime == "TOP10_LONG",
            "total2_down": regime == "SHORT_MODE",
            "total3_weak": regime == "SHORT_MODE",
            "btcd_up": regime == "SHORT_MODE",
            "btcd_down": regime == "TOP10_LONG",
            "tf": "5",
            "confirmed": True,
            "time_ms": 1_779_242_700_000,
            "bar_time_ms": 1_779_242_700_000,
            "signal_id": f"{regime}_5_1779242700000",
        }
    )


if __name__ == "__main__":
    unittest.main()
