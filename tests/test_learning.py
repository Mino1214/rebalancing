from __future__ import annotations

import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from rebalancing.learning.diagnosis import (
    _anthropic_api_key,
    build_diagnosis_prompt,
    parse_diagnosis,
    save_evaluation,
    summarize_records,
)


class LearningDiagnosisTest(unittest.TestCase):
    def test_parse_diagnosis_accepts_json_fence(self) -> None:
        diagnosis = parse_diagnosis(
            """```json
            {
              "summary": "ok",
              "findings": [{"issue": "x", "evidence": "y", "severity": "low"}],
              "param_suggestions": [],
              "pine_suggestions": [],
              "stage_eval": {"current_stage": "BABY", "ready_for_promotion": false, "reason": "data"}
            }
            ```"""
        )

        self.assertIsNotNone(diagnosis)
        assert diagnosis is not None
        self.assertEqual(diagnosis["summary"], "ok")
        self.assertEqual(diagnosis["stage_eval"]["current_stage"], "BABY")

    def test_parse_diagnosis_returns_none_for_bad_json(self) -> None:
        with self.assertLogs("rebalancing.learning.diagnosis", level="WARNING"):
            self.assertIsNone(parse_diagnosis("not json"))

    def test_summarize_records_calculates_core_metrics(self) -> None:
        metrics = summarize_records(
            [
                _record(1, "BULL", True, 5.0),
                _record(2, "BULL", False, -2.0),
                _record(3, "BEAR", True, 0.0),
            ]
        )

        self.assertEqual(metrics["decision_count"], 3)
        self.assertEqual(metrics["should_rebalance_true_count"], 2)
        self.assertEqual(metrics["regime_counts"], {"BEAR": 1, "BULL": 2})
        self.assertEqual(metrics["realized_pnl_total"], 3.0)
        self.assertEqual(metrics["win_rate"], 0.333333)
        self.assertEqual(metrics["regime_performance"]["BULL"]["pnl"], 3.0)

    def test_build_prompt_includes_metrics_and_current_params(self) -> None:
        with patch("rebalancing.learning.diagnosis.load_recent_records", return_value=(_record(1, "BULL", True, 1.0),)):
            prompt = build_diagnosis_prompt(window=1)

        self.assertIn('"decision_count": 1', prompt)
        self.assertIn('"current_bot_params"', prompt)
        self.assertIn('"bull_target_leverage"', prompt)
        self.assertIn('"response_schema"', prompt)

    def test_save_evaluation_writes_row(self) -> None:
        connection = _FakeConnection()
        with patch(
            "rebalancing.learning.diagnosis._with_connection",
            side_effect=lambda write: write(connection),
        ):
            evaluation_id = save_evaluation(
                {
                    "summary": "ok",
                    "findings": [],
                    "param_suggestions": [],
                    "pine_suggestions": [],
                    "stage_eval": {"current_stage": "BABY"},
                },
                window=10,
                raw='{"summary":"ok"}',
            )

        self.assertEqual(evaluation_id, 7)
        self.assertIn("INSERT INTO evaluations", connection.cursor_obj.statements[0])
        self.assertIn("window_size", connection.cursor_obj.statements[0])

    def test_anthropic_api_key_can_load_from_file(self) -> None:
        with patch.dict("os.environ", {"ANTHROPIC_API_KEY_FILE": "/tmp/key-file"}, clear=True):
            with patch("builtins.open", unittest.mock.mock_open(read_data=" secret\n")):
                self.assertEqual(_anthropic_api_key(), "secret")


def _record(identifier: int, regime: str, should_rebalance: bool, pnl: float) -> dict:
    return {
        "id": identifier,
        "ts": datetime(2026, 5, 23, tzinfo=timezone.utc),
        "mode": "paper",
        "regime": regime,
        "raw_regime": regime,
        "market_bias": "BROAD_BULL" if regime == "BULL" else "BROAD_BEAR",
        "regime_score": 80.0,
        "should_rebalance": should_rebalance,
        "risk_action": "NONE",
        "reasons": ["test"],
        "next_state": {},
        "account": {"equity": 1000},
        "positions": [],
        "candidates": [],
        "btc": {},
        "market_internals": {"btc_dominance_pct": 51.0},
        "trade_results": [
            {
                "symbol": "BTCUSDT",
                "realized_pnl": pnl,
                "status": "closed",
            }
        ],
    }


class _FakeConnection:
    def __init__(self) -> None:
        self.cursor_obj = _FakeCursor()

    def cursor(self) -> "_FakeCursor":
        return self.cursor_obj


class _FakeCursor:
    def __init__(self) -> None:
        self.statements: list[str] = []

    def __enter__(self) -> "_FakeCursor":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, statement: str, _params: object = None) -> None:
        self.statements.append(statement)

    def fetchone(self) -> tuple[int]:
        return (7,)


if __name__ == "__main__":
    unittest.main()
