from __future__ import annotations

import unittest
from datetime import datetime, timezone

from rebalancing.models import MarketBias, Regime
from rebalancing.tradingview import TradingViewAlert, TradingViewAlertGate, TradingViewRegime


class TradingViewAlertTest(unittest.TestCase):
    def test_parse_current_payload_shape(self) -> None:
        alert = TradingViewAlert.parse(
            {
                "regime": "TOP10_LONG",
                "target_leverage": 2.0,
                "btc_up": True,
                "total_up": True,
                "total2_up": True,
                "total3_weak": False,
                "btcd_up": False,
                "time": "1760000000000",
            }
        )

        self.assertEqual(alert.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(alert.time_ms, 1_760_000_000_000)
        self.assertEqual(alert.to_regime_bias(), (Regime.BULL, MarketBias.BROAD_BULL))
        self.assertEqual(alert.validate(max_leverage=2.0), tuple())

    def test_rejects_unconfirmed_or_excessive_leverage(self) -> None:
        alert = TradingViewAlert.parse(
            {
                "schema": "crypto_regime_v1",
                "regime": "TOP10_LONG",
                "target_leverage": 2.5,
                "btc_up": True,
                "total_up": True,
                "total2_up": True,
                "total3_weak": False,
                "btcd_up": False,
                "time_ms": 1_760_000_000_000,
                "confirmed": False,
            }
        )

        errors = alert.validate(max_leverage=2.0)

        self.assertIn("target_leverage exceeds configured max leverage", errors)
        self.assertIn("alert is not candle-close confirmed", errors)

    def test_gate_rejects_duplicate_and_stale_alerts(self) -> None:
        now = datetime.fromtimestamp(1_760_000_060, tz=timezone.utc)
        alert = TradingViewAlert.parse(
            {
                "schema": "crypto_regime_v1",
                "regime": "RANGE",
                "target_leverage": 0,
                "btc_up": False,
                "total_up": False,
                "total2_up": False,
                "total3_weak": False,
                "btcd_up": False,
                "time_ms": 1_760_000_000_000,
                "signal_id": "RANGE_240_1760000000000",
                "passphrase": "secret",
            }
        )
        gate = TradingViewAlertGate()

        accepted, errors = gate.accept(
            alert,
            expected_passphrase="secret",
            max_age_seconds=120,
            now=now,
        )
        duplicate, duplicate_errors = gate.accept(
            alert,
            expected_passphrase="secret",
            max_age_seconds=120,
            now=now,
        )

        self.assertTrue(accepted)
        self.assertEqual(errors, tuple())
        self.assertFalse(duplicate)
        self.assertIn("duplicate TradingView alert", duplicate_errors)


if __name__ == "__main__":
    unittest.main()

