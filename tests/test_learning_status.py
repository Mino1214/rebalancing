from __future__ import annotations

import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from rebalancing.learning.status import learning_status_payload


class LearningStatusTest(unittest.TestCase):
    def test_learning_status_payload_summarizes_recent_rows(self) -> None:
        now = datetime(2026, 5, 23, 1, 20, tzinfo=timezone.utc)
        connection = _FakeConnection(
            counts=(2, 1, 1, 3, "BABY"),
            runs=[
                (
                    7,
                    now,
                    "scheduler",
                    100,
                    "paper",
                    "ok",
                    1,
                    "BABY",
                    "JUNIOR",
                    True,
                ),
            ],
            evaluations=[
                (1, now, 100, "range 민감도 조정", True),
            ],
            params=[
                (
                    3,
                    True,
                    now,
                    {
                        "range_target_leverage": 0.5,
                        "confirmation_candles": 2,
                        "min_neutral_hours": 6,
                    },
                ),
            ],
        )

        with patch(
            "rebalancing.learning.status._with_connection",
            side_effect=lambda read: read(connection),
        ):
            payload = learning_status_payload()

        self.assertEqual(payload["stage"], "BABY")
        self.assertEqual(payload["run_count"], 2)
        self.assertEqual(payload["evaluation_count"], 1)
        self.assertEqual(payload["trade_result_count"], 3)
        self.assertEqual(payload["latest_run"]["status"], "ok")
        self.assertEqual(payload["latest_run"]["stage_after"], "JUNIOR")
        self.assertEqual(
            payload["latest_evaluation"]["summary"],
            "range 민감도 조정",
        )
        self.assertEqual(payload["active_params"]["version"], 3)
        self.assertEqual(payload["active_params"]["confirmation_candles"], 2)

    def test_learning_status_payload_falls_back_when_db_is_unavailable(self) -> None:
        with patch(
            "rebalancing.learning.status._with_connection",
            side_effect=RuntimeError("offline"),
        ):
            payload = learning_status_payload()

        self.assertEqual(payload["stage"], "BABY")
        self.assertEqual(payload["run_count"], 0)
        self.assertEqual(payload["runs"], [])
        self.assertIn("offline", payload["error"])


class _FakeConnection:
    def __init__(
        self,
        *,
        counts: tuple,
        runs: list[tuple],
        evaluations: list[tuple],
        params: list[tuple],
    ) -> None:
        self.cursor_obj = _FakeCursor(
            one=counts,
            all_batches=[runs, evaluations, params],
        )

    def cursor(self) -> "_FakeCursor":
        return self.cursor_obj


class _FakeCursor:
    def __init__(self, *, one: tuple, all_batches: list[list[tuple]]) -> None:
        self.one = one
        self.all_batches = list(all_batches)
        self.statements: list[str] = []

    def __enter__(self) -> "_FakeCursor":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, statement: str, _params: object = None) -> None:
        self.statements.append(statement)

    def fetchone(self) -> tuple:
        return self.one

    def fetchall(self) -> list[tuple]:
        return self.all_batches.pop(0)


if __name__ == "__main__":
    unittest.main()
