from __future__ import annotations

import unittest
from datetime import datetime, timezone

from rebalancing.models import AccountSnapshot, RiskAction
from rebalancing.risk import RiskManager


class RiskManagerTest(unittest.TestCase):
    def test_weekly_loss_reduces_half(self) -> None:
        manager = RiskManager()
        result = manager.evaluate(
            AccountSnapshot(
                equity=940,
                wallet_balance=940,
                day_start_equity=1_000,
                week_start_equity=1_000,
                month_start_equity=1_000,
            ),
            datetime(2026, 1, 1, tzinfo=timezone.utc),
        )

        self.assertEqual(result.action, RiskAction.REDUCE_HALF)

    def test_monthly_loss_closes_all_and_pauses(self) -> None:
        manager = RiskManager()
        result = manager.evaluate(
            AccountSnapshot(
                equity=890,
                wallet_balance=890,
                day_start_equity=1_000,
                week_start_equity=1_000,
                month_start_equity=1_000,
            ),
            datetime(2026, 1, 1, tzinfo=timezone.utc),
        )

        self.assertEqual(result.action, RiskAction.CLOSE_ALL_AND_PAUSE)
        self.assertIsNotNone(result.cooldown_until)


if __name__ == "__main__":
    unittest.main()

