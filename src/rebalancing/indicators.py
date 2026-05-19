from __future__ import annotations

from statistics import mean

from .models import BtcMarketSnapshot, Candle


def ema(values: list[float], period: int) -> list[float]:
    if period <= 0:
        raise ValueError("period must be positive")
    if not values:
        raise ValueError("values must not be empty")

    alpha = 2.0 / (period + 1.0)
    output = [values[0]]
    for value in values[1:]:
        output.append(value * alpha + output[-1] * (1.0 - alpha))
    return output


def true_ranges(candles: list[Candle]) -> list[float]:
    if len(candles) < 2:
        return []

    ranges = []
    previous_close = candles[0].close
    for candle in candles[1:]:
        ranges.append(
            max(
                candle.high - candle.low,
                abs(candle.high - previous_close),
                abs(candle.low - previous_close),
            )
        )
        previous_close = candle.close
    return ranges


def atr(candles: list[Candle], period: int = 14) -> list[float]:
    ranges = true_ranges(candles)
    if len(ranges) < period:
        raise ValueError("not enough candles to compute ATR")

    first = mean(ranges[:period])
    output = [first]
    previous = first
    for value in ranges[period:]:
        previous = (previous * (period - 1) + value) / period
        output.append(previous)
    return output


def adx(candles: list[Candle], period: int = 14) -> list[float]:
    if len(candles) < period * 2 + 1:
        raise ValueError("not enough candles to compute ADX")

    trs: list[float] = []
    plus_dm: list[float] = []
    minus_dm: list[float] = []

    for index in range(1, len(candles)):
        current = candles[index]
        previous = candles[index - 1]
        up_move = current.high - previous.high
        down_move = previous.low - current.low

        plus_dm.append(up_move if up_move > down_move and up_move > 0 else 0.0)
        minus_dm.append(down_move if down_move > up_move and down_move > 0 else 0.0)
        trs.append(
            max(
                current.high - current.low,
                abs(current.high - previous.close),
                abs(current.low - previous.close),
            )
        )

    smoothed_tr = sum(trs[:period])
    smoothed_plus = sum(plus_dm[:period])
    smoothed_minus = sum(minus_dm[:period])
    dx_values: list[float] = []
    output: list[float] = []

    for index in range(period, len(trs)):
        if index > period:
            smoothed_tr = smoothed_tr - smoothed_tr / period + trs[index]
            smoothed_plus = smoothed_plus - smoothed_plus / period + plus_dm[index]
            smoothed_minus = smoothed_minus - smoothed_minus / period + minus_dm[index]

        if smoothed_tr == 0:
            dx_values.append(0.0)
            continue

        plus_di = 100.0 * smoothed_plus / smoothed_tr
        minus_di = 100.0 * smoothed_minus / smoothed_tr
        denominator = plus_di + minus_di
        dx = 0.0 if denominator == 0 else 100.0 * abs(plus_di - minus_di) / denominator
        dx_values.append(dx)

        if len(dx_values) == period:
            output.append(mean(dx_values))
        elif len(dx_values) > period:
            output.append((output[-1] * (period - 1) + dx) / period)

    return output


def build_btc_snapshot(daily: list[Candle], four_hour: list[Candle]) -> BtcMarketSnapshot:
    if len(daily) < 201:
        raise ValueError("at least 201 daily candles are required")
    if len(four_hour) < 61:
        raise ValueError("at least 61 four-hour candles are required")

    daily_closes = [candle.close for candle in daily]
    four_hour_closes = [candle.close for candle in four_hour]
    atr_values = atr(daily)
    adx_values = adx(daily)
    latest_atr = atr_values[-1]
    atr_baseline = mean(atr_values[-20:]) if len(atr_values) >= 20 else mean(atr_values)
    volume_baseline = mean([candle.volume for candle in four_hour[-21:-1]])
    change_4h_pct = (four_hour[-1].close / four_hour[-2].close - 1.0) * 100.0

    return BtcMarketSnapshot(
        close_1d=daily[-1].close,
        ema20_1d=ema(daily_closes, 20)[-1],
        ema60_1d=ema(daily_closes, 60)[-1],
        ema200_1d=ema(daily_closes, 200)[-1],
        ema20_4h=ema(four_hour_closes, 20)[-1],
        ema60_4h=ema(four_hour_closes, 60)[-1],
        adx_1d=adx_values[-1],
        change_4h_pct=change_4h_pct,
        atr_1d=latest_atr,
        atr_1d_baseline=atr_baseline,
        volume_4h=four_hour[-1].volume,
        volume_4h_baseline=volume_baseline,
    )

