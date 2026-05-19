from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from rebalancing.models import EngineState, TradeMode
from rebalancing.transitions import TransitionGuard


class TransitionGuardTest(unittest.TestCase):
    def test_opposite_direction_must_pass_through_neutral(self) -> None:
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        guard = TransitionGuard()
        state = EngineState(mode=TradeMode.LONG, mode_started_at=now)

        first = guard.apply(TradeMode.SHORT, state, now)
        self.assertEqual(first.mode, TradeMode.NEUTRAL)
        self.assertEqual(first.state.pending_mode, TradeMode.SHORT)

        early = guard.apply(TradeMode.SHORT, first.state, now + timedelta(hours=11))
        self.assertEqual(early.mode, TradeMode.NEUTRAL)

        later = guard.apply(TradeMode.SHORT, first.state, now + timedelta(hours=12))
        self.assertEqual(later.mode, TradeMode.SHORT)


if __name__ == "__main__":
    unittest.main()

