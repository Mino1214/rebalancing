from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from .models import AccountSnapshot, EngineConfig, RiskAction


@dataclass(frozen=True)
class RiskResult:
    action: RiskAction
    reasons: tuple[str, ...]
    cooldown_until: datetime | None = None


class RiskManager:
    def __init__(self, config: EngineConfig | None = None) -> None:
        self.config = config or EngineConfig()

    def evaluate(self, account: AccountSnapshot, now: datetime) -> RiskResult:
        day_return = self._return(account.equity, account.day_start_equity)
        week_return = self._return(account.equity, account.week_start_equity)
        month_return = self._return(account.equity, account.month_start_equity)

        if month_return <= self.config.monthly_loss_limit_pct:
            return RiskResult(
                action=RiskAction.CLOSE_ALL_AND_PAUSE,
                reasons=(f"monthly loss {month_return:.2%} breached",),
                cooldown_until=now + timedelta(hours=self.config.post_loss_cooldown_hours),
            )

        if week_return <= self.config.weekly_loss_limit_pct:
            return RiskResult(
                action=RiskAction.REDUCE_HALF,
                reasons=(f"weekly loss {week_return:.2%} breached",),
            )

        if day_return <= self.config.daily_loss_limit_pct:
            return RiskResult(
                action=RiskAction.BLOCK_NEW_ENTRIES,
                reasons=(f"daily loss {day_return:.2%} breached",),
            )

        return RiskResult(action=RiskAction.NONE, reasons=tuple())

    def _return(self, equity: float, start_equity: float) -> float:
        if start_equity <= 0:
            return 0.0
        return equity / start_equity - 1.0

