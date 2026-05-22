from __future__ import annotations

import unittest

from rebalancing.status import _sorted_events, _tv_signal_reason, _tv_signal_score


class StatusPayloadTest(unittest.TestCase):
    def test_tv_signal_score_uses_tradingview_flag_weights(self) -> None:
        score = _tv_signal_score(
            {
                "btc_up": True,
                "btc_down": False,
                "total_up": True,
                "total_down": False,
                "total2_up": True,
                "total2_down": False,
                "total3_up": True,
                "total3_weak": False,
                "btcd_up": True,
                "btcd_down": False,
            }
        )

        self.assertEqual(score, 80.0)

    def test_tv_signal_score_matches_existing_pine_without_total3_up(self) -> None:
        score = _tv_signal_score(
            {
                "btc_up": True,
                "btc_down": False,
                "total_up": True,
                "total_down": False,
                "total2_up": True,
                "total2_down": False,
                "total3_up": None,
                "total3_weak": False,
                "btcd_up": True,
                "btcd_down": False,
            }
        )

        self.assertEqual(score, 80.0)

    def test_tv_signal_reason_explains_legacy_current_no_entry_conflict(self) -> None:
        reason = _tv_signal_reason(
            {
                "regime": "RANGE",
                "btc_up": True,
                "total_up": True,
                "total2_up": True,
                "btcd_up": True,
            }
        )

        self.assertEqual(reason, "BTC.D up reduces TOP10 leverage")

    def test_tv_signal_reason_prefers_server_decision_reason(self) -> None:
        reason = _tv_signal_reason(
            {
                "regime": "RANGE",
                "decision_reason": "server kept range",
                "btc_up": True,
                "total_up": True,
                "total2_up": True,
                "btcd_up": True,
            }
        )

        self.assertEqual(reason, "server kept range")

    def test_tv_signal_score_prefers_payload_score_when_available(self) -> None:
        self.assertEqual(_tv_signal_score({"score": "42.5"}), 42.5)

    def test_tv_signal_score_handles_alt_weak_short_flags(self) -> None:
        score = _tv_signal_score(
            {
                "btc_up": False,
                "btc_down": True,
                "total_up": False,
                "total_down": True,
                "total2_up": False,
                "total2_down": True,
                "total3_weak": True,
                "btcd_up": True,
                "btcd_down": False,
            }
        )

        self.assertEqual(score, -100.0)

    def test_events_are_sorted_after_merging_sources(self) -> None:
        events = _sorted_events(
            [{"time": "2026-05-20T09:30:00+00:00", "kind": "ALERT", "message": "alert"}],
            [{"time": "2026-05-20T09:35:00+00:00", "kind": "PAPER_ENTRY", "message": "entry"}],
            [{"time": "2026-05-20T09:34:00+00:00", "kind": "DECISION", "message": "decision"}],
        )

        self.assertEqual([event["kind"] for event in events], ["PAPER_ENTRY", "DECISION", "ALERT"])


if __name__ == "__main__":
    unittest.main()
