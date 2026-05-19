from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timedelta

from .models import EngineConfig, EngineState, TradeMode, is_directional_mode, opposite_mode


@dataclass(frozen=True)
class TransitionResult:
    mode: TradeMode
    state: EngineState
    reason: str | None = None


class TransitionGuard:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()

    def apply(self, desired_mode: TradeMode, state: EngineState, now: datetime) -> TransitionResult:
        if state.cooldown_until is not None and now < state.cooldown_until:
            paused = replace(state, mode=TradeMode.PAUSED)
            return TransitionResult(TradeMode.PAUSED, paused, "cooldown_active")

        if desired_mode == TradeMode.PAUSED:
            next_state = replace(
                state,
                mode=TradeMode.PAUSED,
                mode_started_at=now,
                cooldown_until=now + timedelta(hours=self.config.chaotic_cooldown_hours),
            )
            return TransitionResult(TradeMode.PAUSED, next_state, "paused")

        if desired_mode == TradeMode.NEUTRAL:
            if state.mode == TradeMode.NEUTRAL:
                return TransitionResult(TradeMode.NEUTRAL, replace(state, pending_mode=None), None)

            last_directional = state.mode if is_directional_mode(state.mode) else state.last_directional_mode
            next_state = replace(
                state,
                mode=TradeMode.NEUTRAL,
                mode_started_at=now,
                neutral_since=now,
                pending_mode=None,
                last_directional_mode=last_directional,
            )
            return TransitionResult(TradeMode.NEUTRAL, next_state, "moved_to_neutral")

        if state.mode == desired_mode:
            return TransitionResult(desired_mode, state, None)

        if is_directional_mode(state.mode) and opposite_mode(state.mode) == desired_mode:
            next_state = replace(
                state,
                mode=TradeMode.NEUTRAL,
                mode_started_at=now,
                neutral_since=now,
                pending_mode=desired_mode,
                last_directional_mode=state.mode,
            )
            return TransitionResult(TradeMode.NEUTRAL, next_state, "opposite_signal_requires_neutral")

        if state.mode == TradeMode.PAUSED:
            next_state = replace(
                state,
                mode=TradeMode.NEUTRAL,
                mode_started_at=now,
                neutral_since=now,
                pending_mode=desired_mode,
            )
            return TransitionResult(TradeMode.NEUTRAL, next_state, "leaving_pause_via_neutral")

        if state.mode == TradeMode.NEUTRAL:
            if state.pending_mode == desired_mode:
                neutral_since = state.neutral_since or now
                min_neutral = timedelta(hours=self.config.min_neutral_hours)
                if now - neutral_since < min_neutral:
                    return TransitionResult(TradeMode.NEUTRAL, state, "neutral_cooldown_active")

                next_state = replace(
                    state,
                    mode=desired_mode,
                    mode_started_at=now,
                    pending_mode=None,
                    last_directional_mode=desired_mode,
                )
                return TransitionResult(desired_mode, next_state, "neutral_cooldown_complete")

            if state.pending_mode is not None and desired_mode == state.last_directional_mode:
                next_state = replace(
                    state,
                    mode=desired_mode,
                    mode_started_at=now,
                    pending_mode=None,
                    last_directional_mode=desired_mode,
                )
                return TransitionResult(desired_mode, next_state, "returned_to_previous_direction")

            if state.last_directional_mode is not None and opposite_mode(state.last_directional_mode) == desired_mode:
                next_state = replace(state, pending_mode=desired_mode, neutral_since=state.neutral_since or now)
                return TransitionResult(TradeMode.NEUTRAL, next_state, "new_direction_requires_neutral")

            next_state = replace(
                state,
                mode=desired_mode,
                mode_started_at=now,
                pending_mode=None,
                last_directional_mode=desired_mode,
            )
            return TransitionResult(desired_mode, next_state, "entered_direction")

        return TransitionResult(state.mode, state, None)

