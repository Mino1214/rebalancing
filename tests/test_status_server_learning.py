from __future__ import annotations

import unittest
from unittest.mock import patch

from rebalancing.status_server import _start_learning_scheduler


class StatusServerLearningTest(unittest.TestCase):
    def test_learning_scheduler_stays_disabled_by_default(self) -> None:
        with (
            patch.dict("os.environ", {}, clear=True),
            patch("rebalancing.status_server.Thread") as thread,
        ):
            _start_learning_scheduler()

        thread.assert_not_called()

    def test_learning_scheduler_starts_when_enabled(self) -> None:
        with (
            patch.dict(
                "os.environ",
                {
                    "LEARNING_BACKGROUND_ENABLED": "true",
                    "LEARNING_INTERVAL_SECONDS": "600",
                    "LEARNING_WINDOW": "100",
                    "LEARNING_MODE": "paper",
                },
                clear=True,
            ),
            patch("rebalancing.status_server.Thread") as thread,
        ):
            _start_learning_scheduler()

        thread.assert_called_once()
        self.assertTrue(thread.call_args.kwargs["daemon"])


if __name__ == "__main__":
    unittest.main()
