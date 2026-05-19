from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone

from .models import (
    AccountSnapshot,
    BtcMarketSnapshot,
    CryptoMarketSnapshot,
    EngineConfig,
    EngineState,
    MarketBias,
    MarketCandidate,
    Position,
    RebalanceDecision,
    Regime,
    RiskAction,
    TargetPosition,
    TradeMode,
)
from .orders import OrderPlanner
from .portfolio import PortfolioBuilder
from .regime import RegimeDetector
from .risk import RiskManager
from .timeframes import next_candle_close
from .transitions import TransitionGuard


class RebalancingEngine:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()
        self.regime_detector = RegimeDetector(self.config)
        self.transition_guard = TransitionGuard(self.config)
        self.portfolio_builder = PortfolioBuilder(self.config)
        self.order_planner = OrderPlanner(self.config)
        self.risk_manager = RiskManager(self.config)

    def evaluate(
        self,
        *,
        account: AccountSnapshot,
        candidates: list[MarketCandidate],
        positions: list[Position],
        btc: BtcMarketSnapshot | None = None,
        market: CryptoMarketSnapshot | None = None,
        state: EngineState | None = None,
        now: datetime | None = None,
        force_rebalance: bool = False,
    ) -> RebalanceDecision:
        now = now or datetime.now(timezone.utc)
        state = state or EngineState()
        market_snapshot = self._market_snapshot(btc=btc, market=market)
        reasons: list[str] = []

        next_state, deposit_waiting, deposit_due, deposit_reasons = self._handle_deposit(account, state, now)
        reasons.extend(deposit_reasons)

        regime_result = self.regime_detector.detect(market_snapshot, next_state)
        reasons.extend(regime_result.reasons)
        next_state = replace(
            next_state,
            raw_regime_history=regime_result.history,
            last_confirmed_regime=regime_result.confirmed,
        )

        risk = self.risk_manager.evaluate(account, now)
        reasons.extend(risk.reasons)

        urgent = False
        block_entries = False

        if risk.action == RiskAction.CLOSE_ALL_AND_PAUSE:
            targets = tuple()
            urgent = True
            block_entries = True
            next_state = replace(
                next_state,
                mode=TradeMode.PAUSED,
                mode_started_at=now,
                cooldown_until=risk.cooldown_until,
            )
            reasons.append("monthly risk stop closes all positions")
        elif risk.action == RiskAction.REDUCE_HALF:
            targets = self.portfolio_builder.scale_positions(positions, 0.5)
            urgent = True
            block_entries = True
            reasons.append("weekly risk stop reduces current exposure by 50%")
        elif regime_result.confirmed == Regime.CHAOTIC:
            targets = self.portfolio_builder.scale_positions(positions, 0.5)
            urgent = True
            block_entries = True
            next_state = replace(
                next_state,
                mode=TradeMode.PAUSED,
                mode_started_at=now,
                cooldown_until=now + timedelta(hours=self.config.chaotic_cooldown_hours),
            )
            reasons.append("CHAOTIC regime blocks new entries and cuts current exposure")
        else:
            if risk.action == RiskAction.BLOCK_NEW_ENTRIES:
                block_entries = True

            desired_mode = self._desired_mode(regime_result.confirmed)
            if next_state.mode == TradeMode.LONG and regime_result.raw == Regime.BEAR:
                desired_mode = TradeMode.NEUTRAL
                reasons.append("preliminary BEAR signal closes LONG before any SHORT")
            elif next_state.mode == TradeMode.SHORT and regime_result.raw == Regime.BULL:
                desired_mode = TradeMode.NEUTRAL
                reasons.append("preliminary BULL signal closes SHORT before any LONG")

            transition = self.transition_guard.apply(desired_mode, next_state, now)
            if transition.reason:
                reasons.append(transition.reason)
            next_state = transition.state
            targets = self._build_targets(
                mode=transition.mode,
                account=account,
                btc=market_snapshot.btc,
                candidates=candidates,
                positions=positions,
                state=next_state,
                now=now,
                market_bias=regime_result.bias,
            )

            if transition.mode in {TradeMode.PAUSED, TradeMode.NEUTRAL}:
                block_entries = True
            if deposit_waiting:
                block_entries = True

        scheduled_rebalance = self._regular_rebalance_due(next_state, now) or deposit_due or force_rebalance
        if deposit_due:
            reasons.append("deposit rebalance is due after candle close")
            next_state = replace(next_state, pending_deposit_rebalance_at=None)
        if force_rebalance:
            reasons.append("force_rebalance requested")
        if self._regular_rebalance_due(next_state, now):
            reasons.append("regular rebalance interval elapsed")

        orders = self.order_planner.plan(
            positions=positions,
            targets=targets,
            urgent=urgent,
            block_entries=block_entries,
        )
        should_rebalance = bool(orders) or scheduled_rebalance or risk.action != RiskAction.NONE or regime_result.confirmed == Regime.CHAOTIC

        if should_rebalance:
            next_state = replace(next_state, last_rebalance_at=now)

        return RebalanceDecision(
            now=now,
            raw_regime=regime_result.raw,
            regime=regime_result.confirmed,
            market_bias=regime_result.bias,
            regime_score=regime_result.score,
            mode=next_state.mode,
            target_positions=targets,
            orders=orders,
            risk_action=risk.action,
            should_rebalance=should_rebalance,
            reasons=tuple(reasons),
            next_state=next_state,
        )

    def _build_targets(
        self,
        *,
        mode: TradeMode,
        account: AccountSnapshot,
        btc: BtcMarketSnapshot,
        candidates: list[MarketCandidate],
        positions: list[Position],
        state: EngineState,
        now: datetime,
        market_bias: MarketBias,
    ) -> tuple[TargetPosition, ...]:
        if mode == TradeMode.LONG:
            return self.portfolio_builder.build_long_targets(
                equity=account.equity,
                candidates=candidates,
                leverage=None if market_bias == MarketBias.BTC_ONLY_BULL else self.config.bull_target_leverage,
                market_bias=market_bias,
            )
        if mode == TradeMode.SHORT:
            return self.portfolio_builder.build_short_targets(
                equity=account.equity,
                candidates=candidates,
                btc=btc,
                state=state,
                now=now,
                market_bias=market_bias,
            )
        if mode == TradeMode.NEUTRAL:
            return self.portfolio_builder.build_range_targets(account.equity, positions)
        return tuple(
            TargetPosition(position.symbol, position.side, position.notional)
            for position in positions
        )

    def _market_snapshot(
        self,
        *,
        btc: BtcMarketSnapshot | None,
        market: CryptoMarketSnapshot | None,
    ) -> CryptoMarketSnapshot:
        if market is not None:
            return market
        if btc is None:
            raise ValueError("either btc or market must be provided")
        return CryptoMarketSnapshot(btc=btc)

    def _desired_mode(self, regime: Regime) -> TradeMode:
        if regime == Regime.BULL:
            return TradeMode.LONG
        if regime == Regime.BEAR:
            return TradeMode.SHORT
        if regime == Regime.CHAOTIC:
            return TradeMode.PAUSED
        return TradeMode.NEUTRAL

    def _handle_deposit(
        self,
        account: AccountSnapshot,
        state: EngineState,
        now: datetime,
    ) -> tuple[EngineState, bool, bool, list[str]]:
        reasons: list[str] = []
        next_state = state
        deposit_waiting = False
        deposit_due = False

        if state.last_wallet_balance is None:
            next_state = replace(state, last_wallet_balance=account.wallet_balance)
            return next_state, deposit_waiting, deposit_due, reasons

        wallet_delta = account.wallet_balance - state.last_wallet_balance
        if wallet_delta >= self.config.deposit_min_usdt:
            rebalance_at = next_candle_close(now, self.config.deposit_timeframe_hours)
            next_state = replace(
                state,
                last_wallet_balance=account.wallet_balance,
                pending_deposit_rebalance_at=rebalance_at,
            )
            reasons.append(f"USDT deposit detected: {wallet_delta:.2f}; wait until {rebalance_at.isoformat()}")
        elif abs(wallet_delta) >= self.config.deposit_min_usdt:
            next_state = replace(state, last_wallet_balance=account.wallet_balance)

        if next_state.pending_deposit_rebalance_at is not None:
            if now >= next_state.pending_deposit_rebalance_at:
                deposit_due = True
            else:
                deposit_waiting = True
                reasons.append("deposit rebalance is waiting for next candle close")

        return next_state, deposit_waiting, deposit_due, reasons

    def _regular_rebalance_due(self, state: EngineState, now: datetime) -> bool:
        if state.last_rebalance_at is None:
            return True
        elapsed = now - state.last_rebalance_at
        return elapsed >= timedelta(hours=self.config.regular_rebalance_hours)
