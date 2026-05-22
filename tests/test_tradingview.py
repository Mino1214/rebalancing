from __future__ import annotations

import os
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from rebalancing.models import MarketBias, Regime
from rebalancing.tradingview import (
    TradingViewAction,
    TradingViewAlert,
    TradingViewAlertGate,
    TradingViewRegime,
    finalize_tradingview_alert,
    server_decision_from_flags,
)


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

    def test_server_decision_routes_btc_dominance_uptrend_to_reduced_top10(self) -> None:
        alert = TradingViewAlert.parse(
            _payload(
                btc_up=True,
                total_up=True,
                total2_up=True,
                btcd_up=True,
                btcd_down=False,
            )
        )

        decision = server_decision_from_flags(alert)

        self.assertEqual(decision.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(decision.target_leverage, 1.0)
        self.assertEqual(decision.score, 80.0)
        self.assertEqual(
            decision.reason,
            "Server entry: BTC, TOTAL, TOTAL2 up; diversified TOP10 with reduced leverage because BTC.D is up",
        )

    def test_server_decision_overrides_source_regime_for_top10(self) -> None:
        alert = TradingViewAlert.parse(
            _payload(
                regime="RANGE",
                target_leverage=0.0,
                btc_up=True,
                total_up=True,
                total2_up=True,
                total3_up=True,
                btcd_down=True,
            )
        )

        finalized, decision = finalize_tradingview_alert(alert, max_leverage=1.5)

        self.assertEqual(finalized.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(finalized.target_leverage, 1.5)
        self.assertEqual(finalized.score, 100.0)
        self.assertEqual(decision.source_regime, TradingViewRegime.RANGE)

    def test_server_decision_uses_existing_btc_eth_rule(self) -> None:
        alert = TradingViewAlert.parse(
            _payload(
                btc_up=True,
                total_up=True,
                total2_up=False,
                total2_down=True,
                btcd_up=True,
            )
        )

        decision = server_decision_from_flags(alert)

        self.assertEqual(decision.regime, TradingViewRegime.BTC_ETH_LONG)
        self.assertEqual(decision.target_leverage, 1.2)

    def test_server_decision_keeps_pine_priority_for_alt_weak_short(self) -> None:
        alert = TradingViewAlert.parse(
            _payload(
                btc_down=True,
                total_down=True,
                total2_down=True,
                total3_weak=True,
                btcd_up=True,
            )
        )

        decision = server_decision_from_flags(alert)

        self.assertEqual(decision.regime, TradingViewRegime.ALT_WEAK_SHORT)
        self.assertEqual(decision.target_leverage, 1.0)

    def test_validation_can_treat_regime_as_source_suggestion(self) -> None:
        alert = TradingViewAlert.parse(_payload(regime="TOP10_LONG", target_leverage=12.0))

        errors = alert.validate(
            enforce_target_leverage=False,
            validate_regime_consistency=False,
        )

        self.assertEqual(errors, tuple())

    def test_multi_timeframe_requires_higher_timeframe_alignment(self) -> None:
        payload = _payload(
            btc_down=True,
            total_down=True,
            total2_down=True,
            btcd_up=True,
            signal_id="mtf-long-5m-flip",
        )
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "12h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "8h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "4h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "1h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "5m": _frame(btc_down=True, total_down=True, total2_down=True, btcd_up=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(decision.action, TradingViewAction.ENTER)
        self.assertEqual(decision.target_leverage, 2.0)
        self.assertIn("5m is execution-only", decision.reason)

    def test_multi_timeframe_reduces_when_one_hour_is_mixed_and_5m_is_against(self) -> None:
        payload = _payload(signal_id="mtf-fast-reduce")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "12h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "8h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "4h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "1h": _frame(),
            "5m": _frame(btc_down=True, total_down=True, total2_down=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(decision.action, TradingViewAction.REDUCE)

    def test_multi_timeframe_holds_when_one_hour_and_5m_are_mixed(self) -> None:
        payload = _payload(signal_id="mtf-hold-mixed")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "12h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "8h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "4h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "1h": _frame(),
            "5m": _frame(),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(decision.action, TradingViewAction.HOLD)

    def test_multi_timeframe_reduces_on_fast_5m_reversal_warning(self) -> None:
        payload = _payload(signal_id="mtf-fast-bull-reduce")
        payload["timeframes"] = {
            "24h": _frame(btc_down=True, total_down=True, total2_down=True),
            "12h": _frame(btc_down=True, total_down=True, total2_down=True),
            "8h": _frame(btc_down=True, total_down=True, total2_down=True),
            "4h": _frame(btc_down=True, total_down=True, total2_down=True),
            "1h": _frame(),
            "5m": _frame(btc_fast_bull=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.SHORT_MODE)
        self.assertEqual(decision.action, TradingViewAction.REDUCE)
        self.assertIn("5m is against short", decision.reason)

    def test_multi_timeframe_reduces_when_one_hour_moves_against_regime(self) -> None:
        payload = _payload(signal_id="mtf-reduce")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "12h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "8h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "4h": _frame(btc_up=True, total_up=True, total2_up=True, btcd_down=True),
            "1h": _frame(btc_down=True, total_down=True, total2_down=True),
            "5m": _frame(btc_down=True, total_down=True, total2_down=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.TOP10_LONG)
        self.assertEqual(decision.action, TradingViewAction.REDUCE)

    def test_multi_timeframe_exits_when_24h_and_12h_conflict(self) -> None:
        payload = _payload(signal_id="mtf-conflict")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True),
            "12h": _frame(btc_down=True, total_down=True, total2_down=True),
            "8h": _frame(btc_up=True, total_up=True, total2_up=True),
            "4h": _frame(btc_up=True, total_up=True, total2_up=True),
            "1h": _frame(btc_up=True, total_up=True, total2_up=True),
            "5m": _frame(btc_up=True, total_up=True, total2_up=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.RANGE)
        self.assertEqual(decision.action, TradingViewAction.EXIT)

    def test_multi_timeframe_reduces_when_midframes_conflict_against_direction_filter(self) -> None:
        payload = _payload(signal_id="mtf-midframe-conflict")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True),
            "12h": _frame(btc_up=True, total_up=True, total2_down=True),
            "8h": _frame(btc_down=True, total_down=True, total2_down=True),
            "4h": _frame(btc_down=True, total_down=True, total2_down=True),
            "1h": _frame(btc_up=True, total_up=True, total2_up=True),
            "5m": _frame(btc_up=True, total_up=True, total2_up=True),
        }

        decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.RANGE)
        self.assertEqual(decision.action, TradingViewAction.REDUCE)
        self.assertIn("8h/4h conflict against long", decision.reason)

    def test_probe_entry_override_enters_when_one_hour_aligns(self) -> None:
        payload = _payload(signal_id="mtf-probe-entry")
        payload["timeframes"] = {
            "24h": _frame(btc_up=True, total_up=True, total2_up=True),
            "12h": _frame(btc_up=True, total_up=True, total2_down=True),
            "8h": _frame(btc_down=True, total_down=True, total2_down=True),
            "4h": _frame(btc_down=True, total_down=True, total2_down=True),
            "1h": _frame(btc_up=True, total_up=True, total2_up=True),
            "5m": _frame(btc_down=True, total_down=True, total2_down=True),
        }

        with patch.dict(
            os.environ,
            {
                "ENGINE_TV_ALLOW_PROBE_ENTRIES": "true",
                "ENGINE_TV_PROBE_LEVERAGE": "0.5",
            },
        ):
            decision = server_decision_from_flags(TradingViewAlert.parse(payload))

        self.assertEqual(decision.regime, TradingViewRegime.BTC_ETH_LONG)
        self.assertEqual(decision.action, TradingViewAction.ENTER)
        self.assertEqual(decision.target_leverage, 0.5)
        self.assertIn("probe entry override", decision.reason)


def _payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema": "crypto_regime_v1",
        "source": "tradingview",
        "regime": "RANGE",
        "target_leverage": 0.0,
        "btc_up": False,
        "btc_down": False,
        "total_up": False,
        "total_down": False,
        "total2_up": False,
        "total2_down": False,
        "total3_up": False,
        "total3_weak": False,
        "btcd_up": False,
        "btcd_down": False,
        "tf": "5",
        "confirmed": True,
        "time_ms": 1_779_242_700_000,
        "bar_time_ms": 1_779_242_700_000,
        "signal_id": "test_5_1779242700000",
    }
    payload.update(overrides)
    return payload


def _frame(**overrides: object) -> dict[str, object]:
    frame: dict[str, object] = {
        "btc_up": False,
        "btc_down": False,
        "total_up": False,
        "total_down": False,
        "total2_up": False,
        "total2_down": False,
        "total3_up": False,
        "total3_weak": False,
        "btcd_up": False,
        "btcd_down": False,
    }
    frame.update(overrides)
    return frame


if __name__ == "__main__":
    unittest.main()
