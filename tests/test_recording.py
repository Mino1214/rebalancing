from __future__ import annotations

import os
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from rebalancing.models import (
    EngineState,
    MarketBias,
    OrderSide,
    OrderType,
    PlannedOrder,
    PositionSide,
    RebalanceDecision,
    Regime,
    RiskAction,
    TargetPosition,
    TradeMode,
)
from rebalancing.recording import (
    _decision_record_from_engine,
    _decision_record_from_tradingview,
    _execution_row,
    _planned_order_row,
    _trade_result_row,
    record_decision,
    record_paper_decision,
)
from rebalancing.tradingview import TradingViewAlert, finalize_tradingview_alert


class RecordingTest(unittest.TestCase):
    def test_record_decision_is_fail_open_without_database(self) -> None:
        with patch.dict(os.environ, _empty_db_env(), clear=True):
            self.assertIsNone(record_decision(_decision(), {}, mode="paper"))

    def test_record_decision_writes_decision_snapshot_and_orders(self) -> None:
        connection = _FakeConnection()
        with patch(
            "rebalancing.recording._load_driver",
            return_value=(lambda _dsn: connection, "postgres://test"),
        ):
            decision_id = record_decision(
                _decision(with_order=True),
                {"account": {"equity": 1000}},
                mode="paper",
            )

        self.assertEqual(decision_id, 42)
        self.assertEqual(len(connection.cursor_obj.statements), 3)
        self.assertTrue(connection.committed)
        self.assertTrue(connection.closed)
        self.assertIn("INSERT INTO decisions", connection.cursor_obj.statements[0])
        self.assertIn("INSERT INTO market_snapshots", connection.cursor_obj.statements[1])
        self.assertIn("INSERT INTO planned_orders", connection.cursor_obj.statements[2])

    def test_engine_decision_record_is_json_ready(self) -> None:
        record = _decision_record_from_engine(_decision(), mode="live")

        self.assertEqual(record["mode"], "live")
        self.assertEqual(record["regime"], "BULL")
        self.assertEqual(record["market_bias"], "BROAD_BULL")
        self.assertEqual(record["risk_action"], "NONE")
        self.assertEqual(record["reasons"], ["test reason"])

    def test_planned_order_row_preserves_notional_in_meta(self) -> None:
        row = _planned_order_row(
            PlannedOrder(
                symbol="BTCUSDT",
                side=OrderSide.BUY,
                position_side=PositionSide.LONG,
                notional=125.0,
                order_type=OrderType.MARKET,
                reduce_only=False,
                reason="open_target",
            )
        )

        self.assertEqual(row["symbol"], "BTCUSDT")
        self.assertEqual(row["side"], "BUY")
        self.assertIsNone(row["qty"])
        self.assertEqual(row["meta"]["notional"], 125.0)

    def test_paper_execution_row_derives_quantity_from_notional(self) -> None:
        row = _execution_row(
            {
                "time": "2026-05-23T00:00:00+00:00",
                "symbol": "BTCUSDT",
                "action": "BUY",
                "notional": 100,
                "price": 50,
                "fee": 0.04,
            }
        )

        self.assertIsNotNone(row)
        assert row is not None
        self.assertEqual(str(row["qty"]), "2")
        self.assertEqual(str(row["price"]), "50")
        self.assertEqual(str(row["fee"]), "0.04")

    def test_trade_result_row_records_realized_paper_pnl(self) -> None:
        row = _trade_result_row(
            {
                "time": "2026-05-23T00:00:00+00:00",
                "symbol": "BTCUSDT",
                "action": "CLOSE",
                "net_pnl": 9.5,
            }
        )

        self.assertIsNotNone(row)
        assert row is not None
        self.assertEqual(row["symbol"], "BTCUSDT")
        self.assertEqual(str(row["realized_pnl"]), "9.5")
        self.assertEqual(row["status"], "realized")

    def test_record_paper_decision_writes_trade_results_for_closes(self) -> None:
        connection = _FakeConnection()
        alert, server_decision = finalize_tradingview_alert(_alert())
        with patch(
            "rebalancing.recording._load_driver",
            return_value=(lambda _dsn: connection, "postgres://test"),
        ):
            decision_id = record_paper_decision(
                alert=alert,
                decision=server_decision,
                snapshot={},
                planned_orders=[],
                executions=[
                    {
                        "time": "2026-05-23T00:00:00+00:00",
                        "symbol": "BTCUSDT",
                        "action": "CLOSE",
                        "side": "LONG",
                        "notional": 100,
                        "price": 110,
                        "net_pnl": 9.5,
                    }
                ],
            )

        self.assertEqual(decision_id, 42)
        self.assertTrue(any("INSERT INTO executions" in statement for statement in connection.cursor_obj.statements))
        self.assertTrue(any("INSERT INTO trade_results" in statement for statement in connection.cursor_obj.statements))

    def test_tradingview_decision_maps_to_engine_regime(self) -> None:
        alert, server_decision = finalize_tradingview_alert(_alert())
        record = _decision_record_from_tradingview(alert, server_decision, mode="paper")

        self.assertEqual(record["mode"], "paper")
        self.assertEqual(record["regime"], "BULL")
        self.assertEqual(record["market_bias"], "BROAD_BULL")
        self.assertEqual(record["risk_action"], "NONE")
        self.assertIn("TradingView action=ENTER", record["reasons"])


def _decision(*, with_order: bool = False) -> RebalanceDecision:
    orders = tuple()
    if with_order:
        orders = (
            PlannedOrder(
                symbol="BTCUSDT",
                side=OrderSide.BUY,
                position_side=PositionSide.LONG,
                notional=125.0,
                order_type=OrderType.MARKET,
                reduce_only=False,
                reason="open_target",
            ),
        )
    return RebalanceDecision(
        now=datetime(2026, 5, 23, tzinfo=timezone.utc),
        raw_regime=Regime.BULL,
        regime=Regime.BULL,
        market_bias=MarketBias.BROAD_BULL,
        regime_score=80.0,
        mode=TradeMode.LONG,
        target_positions=(TargetPosition("BTCUSDT", PositionSide.LONG, 100.0, 1.0),),
        orders=orders,
        risk_action=RiskAction.NONE,
        should_rebalance=True,
        reasons=("test reason",),
        next_state=EngineState(mode=TradeMode.LONG),
    )


def _alert() -> TradingViewAlert:
    return TradingViewAlert.parse(
        {
            "schema": "crypto_regime_v1",
            "source": "tradingview",
            "regime": "RANGE",
            "target_leverage": 0,
            "btc_up": True,
            "btc_down": False,
            "total_up": True,
            "total_down": False,
            "total2_up": True,
            "total2_down": False,
            "total3_weak": False,
            "btcd_up": False,
            "btcd_down": True,
            "tf": "5",
            "confirmed": True,
            "time_ms": 1_779_242_700_000,
            "bar_time_ms": 1_779_242_700_000,
            "signal_id": "sig",
        }
    )


def _empty_db_env() -> dict[str, str]:
    return {
        "PATH": os.environ.get("PATH", ""),
    }


class _FakeConnection:
    def __init__(self) -> None:
        self.cursor_obj = _FakeCursor()
        self.committed = False
        self.rolled_back = False
        self.closed = False

    def cursor(self) -> "_FakeCursor":
        return self.cursor_obj

    def commit(self) -> None:
        self.committed = True

    def rollback(self) -> None:
        self.rolled_back = True

    def close(self) -> None:
        self.closed = True


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
        return (42,)


if __name__ == "__main__":
    unittest.main()
