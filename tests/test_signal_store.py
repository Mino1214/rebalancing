from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from rebalancing.signal_store import (
    expected_engine_webhook_token,
    expected_tradingview_passphrase,
    record_tradingview_alert,
    recent_tradingview_alerts,
    tradingview_alert_events,
)


class SignalStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self._old_env = {
            key: os.environ.get(key)
            for key in (
                "ENGINE_WEBHOOK_TOKEN",
                "ENGINE_WEBHOOK_TOKEN_FILE",
                "ENGINE_TV_MAX_ALERT_AGE_SECONDS",
                "TV_WEBHOOK_PASSPHRASE",
                "TV_WEBHOOK_PASSPHRASE_FILE",
            )
        }
        os.environ["ENGINE_TV_MAX_ALERT_AGE_SECONDS"] = "0"

    def tearDown(self) -> None:
        for key, value in self._old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_records_alert_and_strips_passphrase(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "signals.json"
            record, duplicate = record_tradingview_alert(_payload("sig-1"), path=path)

            self.assertFalse(duplicate)
            self.assertEqual(record["signal_id"], "sig-1")
            self.assertEqual(record["regime"], "TOP10_LONG")
            self.assertEqual(record["target_leverage"], 1.0)
            self.assertEqual(record["decision_source"], "server")
            self.assertEqual(record["decision_action"], "ENTER")
            self.assertEqual(record["source_regime"], "RANGE")
            self.assertEqual(record["score"], 80.0)
            self.assertNotIn("passphrase", record)
            self.assertEqual(recent_tradingview_alerts(path=path)[0]["signal_id"], "sig-1")

    def test_server_decision_overrides_stored_source_regime(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "signals.json"
            payload = _payload("sig-top10")
            payload.update(
                {
                    "regime": "RANGE",
                    "target_leverage": 0,
                    "btcd_up": False,
                    "btcd_down": True,
                    "total3_up": True,
                }
            )

            record, duplicate = record_tradingview_alert(payload, path=path)

            self.assertFalse(duplicate)
            self.assertEqual(record["source_regime"], "RANGE")
            self.assertEqual(record["regime"], "TOP10_LONG")
            self.assertEqual(record["target_leverage"], 2.0)
            self.assertEqual(record["score"], 100.0)

    def test_duplicate_signal_id_is_not_appended(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "signals.json"
            first, first_duplicate = record_tradingview_alert(_payload("same"), path=path)
            second, second_duplicate = record_tradingview_alert(_payload("same"), path=path)

            self.assertFalse(first_duplicate)
            self.assertTrue(second_duplicate)
            self.assertEqual(first, second)
            self.assertEqual(len(recent_tradingview_alerts(path=path)), 1)

    def test_event_payload_is_app_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "signals.json"
            record_tradingview_alert(_payload("sig-event"), path=path)

            events = tradingview_alert_events(path=path)

            self.assertEqual(events[0]["kind"], "ALERT")
            self.assertIn("TradingView TOP10_LONG", events[0]["message"])

    def test_reads_webhook_token_from_file(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            token_path = Path(tempdir) / "token"
            token_path.write_text("abc123\n", encoding="utf-8")
            os.environ.pop("ENGINE_WEBHOOK_TOKEN", None)
            os.environ["ENGINE_WEBHOOK_TOKEN_FILE"] = str(token_path)

            self.assertEqual(expected_engine_webhook_token(), "abc123")

    def test_reads_tradingview_passphrase_from_file(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            token_path = Path(tempdir) / "tv-passphrase"
            token_path.write_text("tv-secret\n", encoding="utf-8")
            os.environ.pop("TV_WEBHOOK_PASSPHRASE", None)
            os.environ["TV_WEBHOOK_PASSPHRASE_FILE"] = str(token_path)

            self.assertEqual(expected_tradingview_passphrase(), "tv-secret")


def _payload(signal_id: str) -> dict[str, object]:
    return {
        "schema": "crypto_regime_v1",
        "source": "tradingview",
        "passphrase": "secret",
        "regime": "RANGE",
        "target_leverage": 0,
        "btc_up": True,
        "btc_down": False,
        "total_up": True,
        "total_down": False,
        "total2_up": True,
        "total2_down": False,
        "total3_weak": False,
        "btcd_up": True,
        "btcd_down": False,
        "tf": "5",
        "confirmed": True,
        "time_ms": 1_779_214_500_000,
        "bar_time_ms": 1_779_214_500_000,
        "received_at_ms": 1_779_214_501_000,
        "signal_id": signal_id,
    }


if __name__ == "__main__":
    unittest.main()
