from __future__ import annotations

from datetime import datetime, timedelta
from math import floor


def next_candle_close(now: datetime, timeframe_hours: int) -> datetime:
    if timeframe_hours <= 0:
        raise ValueError("timeframe_hours must be positive")

    start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elapsed_seconds = (now - start_of_day).total_seconds()
    frame_seconds = timeframe_hours * 60 * 60
    next_frame = floor(elapsed_seconds / frame_seconds) + 1
    return start_of_day + timedelta(seconds=next_frame * frame_seconds)

