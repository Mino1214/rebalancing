from __future__ import annotations

import unittest

from rebalancing.models import EngineConfig, OrderSide, OrderType, Position, PositionSide, TargetPosition
from rebalancing.orders import OrderPlanner


class OrderPlannerTest(unittest.TestCase):
    def test_opposite_target_closes_first_without_opening_same_cycle(self) -> None:
        planner = OrderPlanner(EngineConfig(order_split_notional=1_000))
        orders = planner.plan(
            positions=[Position("BTCUSDT", PositionSide.LONG, 400)],
            targets=(TargetPosition("BTCUSDT", PositionSide.SHORT, 400),),
        )

        self.assertEqual(len(orders), 1)
        self.assertEqual(orders[0].side, OrderSide.SELL)
        self.assertEqual(orders[0].position_side, PositionSide.LONG)
        self.assertTrue(orders[0].reduce_only)

    def test_large_entries_are_split_as_limit_orders(self) -> None:
        planner = OrderPlanner(EngineConfig(order_split_notional=200))
        orders = planner.plan(
            positions=[],
            targets=(TargetPosition("BTCUSDT", PositionSide.LONG, 600),),
        )

        self.assertEqual(len(orders), 3)
        self.assertTrue(all(order.order_type == OrderType.LIMIT for order in orders))
        self.assertTrue(all(not order.reduce_only for order in orders))
        self.assertAlmostEqual(sum(order.notional for order in orders), 600)


if __name__ == "__main__":
    unittest.main()

