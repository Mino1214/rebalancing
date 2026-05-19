from __future__ import annotations

from math import ceil

from .models import EngineConfig, OrderSide, OrderType, PlannedOrder, Position, PositionSide, TargetPosition


class OrderPlanner:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()

    def plan(
        self,
        positions: list[Position],
        targets: tuple[TargetPosition, ...],
        *,
        urgent: bool = False,
        block_entries: bool = False,
    ) -> tuple[PlannedOrder, ...]:
        orders: list[PlannedOrder] = []
        current = {(position.symbol, position.side): position for position in positions}
        target = {(target.symbol, target.side): target for target in targets}
        symbols_closed_for_flip: set[str] = set()

        for position in positions:
            same_target = target.get((position.symbol, position.side))
            opposite_target_exists = any(
                candidate.symbol == position.symbol and candidate.side != position.side for candidate in targets
            )

            if same_target is None:
                orders.extend(
                    self._split_order(
                        symbol=position.symbol,
                        position_side=position.side,
                        notional=position.notional,
                        reduce_only=True,
                        urgent=urgent,
                        reason="close_unwanted_or_opposite_position",
                    )
                )
                if opposite_target_exists:
                    symbols_closed_for_flip.add(position.symbol)
                continue

            excess = position.notional - same_target.notional
            if excess > 0 and self._drifted(excess, same_target.notional):
                orders.extend(
                    self._split_order(
                        symbol=position.symbol,
                        position_side=position.side,
                        notional=excess,
                        reduce_only=True,
                        urgent=urgent,
                        reason="reduce_excess_exposure",
                    )
                )

        if block_entries:
            return tuple(orders)

        for target_position in targets:
            if target_position.symbol in symbols_closed_for_flip:
                continue

            current_position = current.get((target_position.symbol, target_position.side))
            current_notional = current_position.notional if current_position is not None else 0.0
            deficit = target_position.notional - current_notional
            if deficit > 0 and self._drifted(deficit, target_position.notional):
                orders.extend(
                    self._split_order(
                        symbol=target_position.symbol,
                        position_side=target_position.side,
                        notional=deficit,
                        reduce_only=False,
                        urgent=False,
                        reason="increase_to_target_exposure",
                    )
                )

        return tuple(orders)

    def has_drift(self, positions: list[Position], targets: tuple[TargetPosition, ...]) -> bool:
        return bool(self.plan(positions, targets))

    def _drifted(self, delta: float, target_notional: float) -> bool:
        if delta < self.config.min_order_notional:
            return False
        if target_notional <= 0:
            return True
        return delta / target_notional >= self.config.drift_threshold

    def _split_order(
        self,
        *,
        symbol: str,
        position_side: PositionSide,
        notional: float,
        reduce_only: bool,
        urgent: bool,
        reason: str,
    ) -> tuple[PlannedOrder, ...]:
        if notional < self.config.min_order_notional:
            return tuple()

        parts = max(1, ceil(notional / self.config.order_split_notional))
        child_notional = notional / parts
        side = self._order_side(position_side, reduce_only)
        order_type = OrderType.MARKET if reduce_only and urgent else OrderType.LIMIT

        return tuple(
            PlannedOrder(
                symbol=symbol,
                side=side,
                position_side=position_side,
                notional=child_notional,
                order_type=order_type,
                reduce_only=reduce_only,
                reason=reason,
            )
            for _ in range(parts)
        )

    def _order_side(self, position_side: PositionSide, reduce_only: bool) -> OrderSide:
        if position_side == PositionSide.LONG:
            return OrderSide.SELL if reduce_only else OrderSide.BUY
        return OrderSide.BUY if reduce_only else OrderSide.SELL

