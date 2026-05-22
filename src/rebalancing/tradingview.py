from __future__ import annotations

import json
import os
from dataclasses import dataclass, field, replace
from datetime import datetime, timezone
from enum import StrEnum
from typing import Any, Mapping

from .models import MarketBias, Regime


class TradingViewRegime(StrEnum):
    TOP10_LONG = "TOP10_LONG"
    BTC_ETH_LONG = "BTC_ETH_LONG"
    ALT_WEAK_SHORT = "ALT_WEAK_SHORT"
    SHORT_MODE = "SHORT_MODE"
    RANGE = "RANGE"
    CHAOTIC = "CHAOTIC"


class TradingViewAction(StrEnum):
    ENTER = "ENTER"
    HOLD = "HOLD"
    REDUCE = "REDUCE"
    EXIT = "EXIT"


class TradingViewAlertError(ValueError):
    pass


@dataclass(frozen=True)
class TradingViewServerDecision:
    regime: TradingViewRegime
    target_leverage: float
    score: float
    reason: str
    source_regime: TradingViewRegime
    source_target_leverage: float
    action: TradingViewAction = TradingViewAction.ENTER


@dataclass(frozen=True)
class TradingViewAlert:
    regime: TradingViewRegime
    target_leverage: float
    btc_up: bool
    total_up: bool
    total2_up: bool
    total3_weak: bool
    btcd_up: bool
    time_ms: int
    schema: str = "crypto_regime_v1"
    source: str = "tradingview"
    tf: str | None = None
    bar_time_ms: int | None = None
    signal_id: str | None = None
    confirmed: bool = True
    score: float | None = None
    decision_action: TradingViewAction | None = None
    btc_down: bool | None = None
    btc_fast_bull: bool | None = None
    btc_fast_bear: bool | None = None
    total_down: bool | None = None
    total2_down: bool | None = None
    total3_up: bool | None = None
    btcd_down: bool | None = None
    timeframes: Mapping[str, Any] = field(default_factory=dict, repr=False, compare=False)
    passphrase: str | None = field(default=None, repr=False)
    raw: Mapping[str, Any] = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def parse(cls, payload: str | bytes | Mapping[str, Any]) -> "TradingViewAlert":
        data = cls._decode_payload(payload)
        try:
            return cls(
                schema=str(data.get("schema", "crypto_regime_v1")),
                source=str(data.get("source", "tradingview")),
                regime=TradingViewRegime(str(data["regime"])),
                target_leverage=float(data["target_leverage"]),
                btc_up=cls._bool(data["btc_up"], "btc_up"),
                total_up=cls._bool(data["total_up"], "total_up"),
                total2_up=cls._bool(data["total2_up"], "total2_up"),
                total3_weak=cls._bool(data["total3_weak"], "total3_weak"),
                btcd_up=cls._bool(data["btcd_up"], "btcd_up"),
                time_ms=cls._int(data.get("time_ms", data.get("time")), "time_ms"),
                tf=str(data["tf"]) if "tf" in data else None,
                bar_time_ms=cls._optional_int(data.get("bar_time_ms"), "bar_time_ms"),
                signal_id=str(data["signal_id"]) if "signal_id" in data else None,
                confirmed=cls._bool(data.get("confirmed", True), "confirmed"),
                score=float(data["score"]) if "score" in data else None,
                decision_action=cls._optional_action(data.get("decision_action")),
                btc_down=cls._optional_bool(data.get("btc_down"), "btc_down"),
                btc_fast_bull=cls._optional_bool(data.get("btc_fast_bull"), "btc_fast_bull"),
                btc_fast_bear=cls._optional_bool(data.get("btc_fast_bear"), "btc_fast_bear"),
                total_down=cls._optional_bool(data.get("total_down"), "total_down"),
                total2_down=cls._optional_bool(data.get("total2_down"), "total2_down"),
                total3_up=cls._optional_bool(data.get("total3_up"), "total3_up"),
                btcd_down=cls._optional_bool(data.get("btcd_down"), "btcd_down"),
                timeframes=cls._timeframes(data.get("timeframes")),
                passphrase=str(data["passphrase"]) if "passphrase" in data else None,
                raw=data,
            )
        except KeyError as exc:
            raise TradingViewAlertError(f"missing required TradingView alert field: {exc.args[0]}") from exc
        except ValueError as exc:
            raise TradingViewAlertError(str(exc)) from exc

    def validate(
        self,
        *,
        max_leverage: float = 2.0,
        expected_passphrase: str | None = None,
        max_age_seconds: int | None = None,
        now: datetime | None = None,
        enforce_target_leverage: bool = True,
        validate_regime_consistency: bool = True,
    ) -> tuple[str, ...]:
        errors: list[str] = []

        if enforce_target_leverage:
            if self.target_leverage < 0:
                errors.append("target_leverage must be non-negative")
            if self.target_leverage > max_leverage:
                errors.append("target_leverage exceeds configured max leverage")
        if not self.confirmed:
            errors.append("alert is not candle-close confirmed")
        if expected_passphrase is not None and self.passphrase != expected_passphrase:
            errors.append("invalid TradingView passphrase")
        if self.schema != "crypto_regime_v1":
            errors.append("unsupported TradingView alert schema")

        if max_age_seconds is not None:
            now = now or datetime.now(timezone.utc)
            age_seconds = now.timestamp() - self.time_ms / 1000
            if age_seconds > max_age_seconds:
                errors.append("stale TradingView alert")
            if age_seconds < -60:
                errors.append("TradingView alert time is too far in the future")

        errors.extend(self._direction_consistency_errors())
        errors.extend(self._timeframe_consistency_errors())
        if validate_regime_consistency:
            errors.extend(self._regime_consistency_errors())
        return tuple(errors)

    def assert_valid(self, **kwargs: Any) -> None:
        errors = self.validate(**kwargs)
        if errors:
            raise TradingViewAlertError("; ".join(errors))

    def to_regime_bias(self) -> tuple[Regime, MarketBias]:
        return {
            TradingViewRegime.TOP10_LONG: (Regime.BULL, MarketBias.BROAD_BULL),
            TradingViewRegime.BTC_ETH_LONG: (Regime.BULL, MarketBias.BTC_ONLY_BULL),
            TradingViewRegime.ALT_WEAK_SHORT: (Regime.BEAR, MarketBias.ALT_WEAK_BEAR),
            TradingViewRegime.SHORT_MODE: (Regime.BEAR, MarketBias.BROAD_BEAR),
            TradingViewRegime.RANGE: (Regime.RANGE, MarketBias.RANGE),
            TradingViewRegime.CHAOTIC: (Regime.CHAOTIC, MarketBias.CHAOTIC),
        }[self.regime]

    def with_server_decision(self, decision: TradingViewServerDecision) -> "TradingViewAlert":
        return replace(
            self,
            regime=decision.regime,
            target_leverage=decision.target_leverage,
            score=decision.score,
            decision_action=decision.action,
        )

    def dedupe_key(self) -> str:
        if self.signal_id:
            return self.signal_id
        bar_time = self.bar_time_ms if self.bar_time_ms is not None else self.time_ms
        return f"{self.schema}:{self.tf or 'unknown'}:{bar_time}:{self.regime}"

    def _consistency_errors(self) -> tuple[str, ...]:
        return self._direction_consistency_errors() + self._regime_consistency_errors()

    def _direction_consistency_errors(self) -> tuple[str, ...]:
        errors: list[str] = []
        if self.btc_down is not None and self.btc_up and self.btc_down:
            errors.append("btc_up and btc_down cannot both be true")
        if self.btc_fast_bull and self.btc_fast_bear:
            errors.append("btc_fast_bull and btc_fast_bear cannot both be true")
        if self.total_down is not None and self.total_up and self.total_down:
            errors.append("total_up and total_down cannot both be true")
        if self.total2_down is not None and self.total2_up and self.total2_down:
            errors.append("total2_up and total2_down cannot both be true")
        if self.total3_up is not None and self.total3_up and self.total3_weak:
            errors.append("total3_up and total3_weak cannot both be true")
        if self.btcd_down is not None and self.btcd_up and self.btcd_down:
            errors.append("btcd_up and btcd_down cannot both be true")
        return tuple(errors)

    def _timeframe_consistency_errors(self) -> tuple[str, ...]:
        errors: list[str] = []
        for name, raw in self.timeframes.items():
            if not isinstance(raw, Mapping):
                continue
            if _raw_bool(raw, "btc_up", False) and _raw_bool(raw, "btc_down", False):
                errors.append(f"{name}: btc_up and btc_down cannot both be true")
            if _raw_bool(raw, "btc_fast_bull", False) and _raw_bool(raw, "btc_fast_bear", False):
                errors.append(f"{name}: btc_fast_bull and btc_fast_bear cannot both be true")
            if _raw_bool(raw, "total_up", False) and _raw_bool(raw, "total_down", False):
                errors.append(f"{name}: total_up and total_down cannot both be true")
            if _raw_bool(raw, "total2_up", False) and _raw_bool(raw, "total2_down", False):
                errors.append(f"{name}: total2_up and total2_down cannot both be true")
            if _raw_bool(raw, "total3_up", False) and _raw_bool(raw, "total3_weak", False):
                errors.append(f"{name}: total3_up and total3_weak cannot both be true")
            if _raw_bool(raw, "btcd_up", False) and _raw_bool(raw, "btcd_down", False):
                errors.append(f"{name}: btcd_up and btcd_down cannot both be true")
        return tuple(errors)

    def _regime_consistency_errors(self) -> tuple[str, ...]:
        errors: list[str] = []
        if self.regime == TradingViewRegime.TOP10_LONG and not (self.btc_up and self.total_up and self.total2_up):
            errors.append("TOP10_LONG requires btc_up, total_up, and total2_up")
        if self.regime == TradingViewRegime.BTC_ETH_LONG and not (self.btc_up and self.total_up and self.btcd_up):
            errors.append("BTC_ETH_LONG requires btc_up, total_up, and btcd_up")
        if self.regime == TradingViewRegime.ALT_WEAK_SHORT and not (self.total3_weak and self.btcd_up):
            errors.append("ALT_WEAK_SHORT requires total3_weak and btcd_up")
        return tuple(errors)

    @staticmethod
    def _decode_payload(payload: str | bytes | Mapping[str, Any]) -> dict[str, Any]:
        if isinstance(payload, Mapping):
            return dict(payload)
        if isinstance(payload, bytes):
            payload = payload.decode("utf-8")
        try:
            decoded = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise TradingViewAlertError(f"invalid JSON payload: {exc}") from exc
        if not isinstance(decoded, dict):
            raise TradingViewAlertError("TradingView payload must be a JSON object")
        return decoded

    @staticmethod
    def _bool(value: Any, field_name: str) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            lowered = value.lower()
            if lowered == "true":
                return True
            if lowered == "false":
                return False
        raise TradingViewAlertError(f"{field_name} must be a boolean")

    @classmethod
    def _optional_bool(cls, value: Any, field_name: str) -> bool | None:
        if value is None:
            return None
        return cls._bool(value, field_name)

    @staticmethod
    def _int(value: Any, field_name: str) -> int:
        if value is None:
            raise TradingViewAlertError(f"{field_name} is required")
        try:
            return int(value)
        except (TypeError, ValueError) as exc:
            raise TradingViewAlertError(f"{field_name} must be an integer timestamp in milliseconds") from exc

    @classmethod
    def _optional_int(cls, value: Any, field_name: str) -> int | None:
        if value is None:
            return None
        return cls._int(value, field_name)

    @staticmethod
    def _optional_action(value: Any) -> TradingViewAction | None:
        if value is None:
            return None
        return TradingViewAction(str(value))

    @staticmethod
    def _timeframes(value: Any) -> Mapping[str, Any]:
        if not isinstance(value, Mapping):
            return {}
        return dict(value)


def finalize_tradingview_alert(
    alert: TradingViewAlert,
    *,
    max_leverage: float = 2.0,
) -> tuple[TradingViewAlert, TradingViewServerDecision]:
    decision = server_decision_from_flags(alert, max_leverage=max_leverage)
    return alert.with_server_decision(decision), decision


@dataclass(frozen=True)
class _TimeframeFlags:
    name: str
    btc_up: bool
    btc_down: bool
    btc_fast_bull: bool
    btc_fast_bear: bool
    total_up: bool
    total_down: bool
    total2_up: bool
    total2_down: bool
    total3_up: bool
    total3_weak: bool
    btcd_up: bool
    btcd_down: bool


def server_decision_from_flags(
    alert: TradingViewAlert,
    *,
    max_leverage: float = 2.0,
) -> TradingViewServerDecision:
    if alert.timeframes:
        return _multi_timeframe_decision_from_flags(alert, max_leverage=max_leverage)

    return _single_timeframe_decision_from_flags(alert, max_leverage=max_leverage)


def _single_timeframe_decision_from_flags(
    alert: TradingViewAlert,
    *,
    max_leverage: float = 2.0,
) -> TradingViewServerDecision:
    strong_long = alert.btc_up and alert.total_up and alert.total2_up and alert.btcd_down is True
    btc_dominance_long = alert.btc_up and alert.total_up and alert.total2_up and alert.btcd_up
    btc_only_long = alert.btc_up and alert.total_up and not alert.total2_up and alert.btcd_up
    bear_mode = alert.btc_down is True and alert.total_down is True and alert.total2_down is True
    alt_weak_short = alert.btc_down is True and alert.total3_weak and alert.btcd_up

    if strong_long:
        regime = TradingViewRegime.TOP10_LONG
        target_leverage = 2.0
    elif btc_dominance_long:
        regime = TradingViewRegime.TOP10_LONG
        target_leverage = 1.0
    elif btc_only_long:
        regime = TradingViewRegime.BTC_ETH_LONG
        target_leverage = 1.2
    elif alt_weak_short:
        regime = TradingViewRegime.ALT_WEAK_SHORT
        target_leverage = 1.0
    elif bear_mode:
        regime = TradingViewRegime.SHORT_MODE
        target_leverage = 0.8
    else:
        regime = TradingViewRegime.RANGE
        target_leverage = 0.0

    target_leverage = max(0.0, min(target_leverage, max_leverage))
    action = TradingViewAction.EXIT if regime in {TradingViewRegime.RANGE, TradingViewRegime.CHAOTIC} else TradingViewAction.ENTER
    return TradingViewServerDecision(
        regime=regime,
        target_leverage=target_leverage,
        score=tradingview_flag_score(alert),
        reason=tradingview_decision_reason(alert, regime),
        source_regime=alert.regime,
        source_target_leverage=alert.target_leverage,
        action=action,
    )


def _multi_timeframe_decision_from_flags(
    alert: TradingViewAlert,
    *,
    max_leverage: float = 2.0,
) -> TradingViewServerDecision:
    daily = _timeframe_flags(alert, "24h")
    twelve_hour = _timeframe_flags(alert, "12h")
    eight_hour = _timeframe_flags(alert, "8h")
    four_hour = _timeframe_flags(alert, "4h")
    one_hour = _timeframe_flags(alert, "1h")
    five_minute = _timeframe_flags(alert, "5m")

    score = _multi_timeframe_score(daily, twelve_hour, eight_hour, four_hour, one_hour)
    direction_filter = _direction_filter(daily, twelve_hour)
    if direction_filter == "RANGE":
        return _server_decision(
            alert,
            regime=TradingViewRegime.RANGE,
            target_leverage=0.0,
            score=score,
            action=TradingViewAction.EXIT,
            reason="MTF range: 24h/12h direction filter is mixed or conflicted",
            max_leverage=max_leverage,
        )

    if direction_filter == "LONG":
        regime, target_leverage, reason = _confirmed_long_regime(eight_hour, four_hour)
        if regime == TradingViewRegime.RANGE:
            if _probe_entries_enabled() and _core_long(one_hour):
                return _server_decision(
                    alert,
                    regime=TradingViewRegime.BTC_ETH_LONG,
                    target_leverage=_probe_entry_leverage(max_leverage),
                    score=score,
                    action=TradingViewAction.ENTER,
                    reason=(
                        f"{reason}; probe entry override: 1h is aligned with 24h/12h long"
                    ),
                    max_leverage=max_leverage,
                )
            action, timing_reason = _unconfirmed_long_action(eight_hour, four_hour, one_hour, five_minute)
            return _server_decision(
                alert,
                regime=regime,
                target_leverage=0.0,
                score=score,
                action=action,
                reason=f"{reason}; {timing_reason}",
                max_leverage=max_leverage,
            )

        action, timing_reason = _long_timing_action(one_hour, five_minute)
        reason = f"{reason}; {timing_reason}; 5m is execution-only ({_direction_label(five_minute)})"
        return _server_decision(
            alert,
            regime=regime,
            target_leverage=target_leverage,
            score=score,
            action=action,
            reason=reason,
            max_leverage=max_leverage,
        )

    regime, target_leverage, reason = _confirmed_short_regime(eight_hour, four_hour)
    if regime == TradingViewRegime.RANGE:
        if _probe_entries_enabled() and _short_setup(one_hour):
            return _server_decision(
                alert,
                regime=TradingViewRegime.SHORT_MODE,
                target_leverage=_probe_entry_leverage(max_leverage),
                score=score,
                action=TradingViewAction.ENTER,
                reason=(
                    f"{reason}; probe entry override: 1h is aligned with 24h/12h short"
                ),
                max_leverage=max_leverage,
            )
        action, timing_reason = _unconfirmed_short_action(eight_hour, four_hour, one_hour, five_minute)
        return _server_decision(
            alert,
            regime=regime,
            target_leverage=0.0,
            score=score,
            action=action,
            reason=f"{reason}; {timing_reason}",
            max_leverage=max_leverage,
        )

    action, timing_reason = _short_timing_action(one_hour, five_minute)
    reason = f"{reason}; {timing_reason}; 5m is execution-only ({_direction_label(five_minute)})"
    return _server_decision(
        alert,
        regime=regime,
        target_leverage=target_leverage,
        score=score,
        action=action,
        reason=reason,
        max_leverage=max_leverage,
    )


def _server_decision(
    alert: TradingViewAlert,
    *,
    regime: TradingViewRegime,
    target_leverage: float,
    score: float,
    action: TradingViewAction,
    reason: str,
    max_leverage: float,
) -> TradingViewServerDecision:
    return TradingViewServerDecision(
        regime=regime,
        target_leverage=max(0.0, min(target_leverage, max_leverage)),
        score=score,
        reason=reason,
        source_regime=alert.regime,
        source_target_leverage=alert.target_leverage,
        action=action,
    )


def _timeframe_flags(alert: TradingViewAlert, name: str) -> _TimeframeFlags:
    raw = alert.timeframes.get(name)
    if isinstance(raw, Mapping):
        data = raw
    else:
        data = {}

    return _TimeframeFlags(
        name=name,
        btc_up=_raw_bool(data, "btc_up", False),
        btc_down=_raw_bool(data, "btc_down", False),
        btc_fast_bull=_raw_bool(data, "btc_fast_bull", False),
        btc_fast_bear=_raw_bool(data, "btc_fast_bear", False),
        total_up=_raw_bool(data, "total_up", False),
        total_down=_raw_bool(data, "total_down", False),
        total2_up=_raw_bool(data, "total2_up", False),
        total2_down=_raw_bool(data, "total2_down", False),
        total3_up=_raw_bool(data, "total3_up", False),
        total3_weak=_raw_bool(data, "total3_weak", False),
        btcd_up=_raw_bool(data, "btcd_up", False),
        btcd_down=_raw_bool(data, "btcd_down", False),
    )


def _raw_bool(data: Mapping[str, Any], key: str, default: bool) -> bool:
    value = data.get(key, default)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.lower()
        if lowered == "true":
            return True
        if lowered == "false":
            return False
    return default


def _multi_timeframe_score(
    daily: _TimeframeFlags,
    twelve_hour: _TimeframeFlags,
    eight_hour: _TimeframeFlags,
    four_hour: _TimeframeFlags,
    one_hour: _TimeframeFlags,
) -> float:
    return (
        _flag_score(daily) * 0.25
        + _flag_score(twelve_hour) * 0.25
        + _flag_score(eight_hour) * 0.20
        + _flag_score(four_hour) * 0.20
        + _flag_score(one_hour) * 0.10
    )


def _flag_score(flags: _TimeframeFlags) -> float:
    score = 0.0
    score += _flag_pair_score(flags.btc_up, flags.btc_down, 40.0)
    score += _flag_pair_score(flags.total_up, flags.total_down, 25.0)
    score += _flag_pair_score(flags.total2_up, flags.total2_down, 25.0)
    if flags.btcd_down:
        score += 10.0
    elif flags.btcd_up:
        score -= 10.0
    return score


def _direction_filter(daily: _TimeframeFlags, twelve_hour: _TimeframeFlags) -> str:
    directions = {_direction_label(daily), _direction_label(twelve_hour)}
    if directions == {"LONG"}:
        return "LONG"
    if directions == {"SHORT"}:
        return "SHORT"
    return "RANGE"


def _direction_label(flags: _TimeframeFlags) -> str:
    if _core_long(flags) and not _short_setup(flags):
        return "LONG"
    if _short_setup(flags) and not _core_long(flags):
        return "SHORT"
    return "MIXED"


def _core_long(flags: _TimeframeFlags) -> bool:
    return flags.btc_up and flags.total_up


def _broad_long(flags: _TimeframeFlags) -> bool:
    return _core_long(flags) and flags.total2_up


def _short_setup(flags: _TimeframeFlags) -> bool:
    return flags.btc_down and flags.total_down


def _broad_short(flags: _TimeframeFlags) -> bool:
    return _short_setup(flags) and flags.total2_down


def _alt_weak_short(flags: _TimeframeFlags) -> bool:
    return flags.btc_down and flags.total3_weak and flags.btcd_up


def _confirmed_long_regime(
    eight_hour: _TimeframeFlags,
    four_hour: _TimeframeFlags,
) -> tuple[TradingViewRegime, float, str]:
    if _broad_long(eight_hour) and _broad_long(four_hour):
        leverage = 2.0 if eight_hour.btcd_down and four_hour.btcd_down else 1.0
        return (
            TradingViewRegime.TOP10_LONG,
            leverage,
            "MTF long: 24h/12h allow long and 8h/4h confirm broad risk-on",
        )

    if _core_long(eight_hour) and _core_long(four_hour):
        return (
            TradingViewRegime.BTC_ETH_LONG,
            1.2,
            "MTF long: 24h/12h allow long and 8h/4h confirm BTC-led risk-on",
        )

    return (
        TradingViewRegime.RANGE,
        0.0,
        "MTF hold: 24h/12h allow long but 8h/4h have not confirmed a long regime",
    )


def _confirmed_short_regime(
    eight_hour: _TimeframeFlags,
    four_hour: _TimeframeFlags,
) -> tuple[TradingViewRegime, float, str]:
    if _alt_weak_short(eight_hour) and _alt_weak_short(four_hour):
        return (
            TradingViewRegime.ALT_WEAK_SHORT,
            1.0,
            "MTF short: 24h/12h allow short and 8h/4h confirm alt weakness",
        )

    if _broad_short(eight_hour) and _broad_short(four_hour):
        return (
            TradingViewRegime.SHORT_MODE,
            0.8,
            "MTF short: 24h/12h allow short and 8h/4h confirm broad risk-off",
        )

    return (
        TradingViewRegime.RANGE,
        0.0,
        "MTF hold: 24h/12h allow short but 8h/4h have not confirmed a short regime",
    )


def _unconfirmed_long_action(
    eight_hour: _TimeframeFlags,
    four_hour: _TimeframeFlags,
    one_hour: _TimeframeFlags,
    five_minute: _TimeframeFlags,
) -> tuple[TradingViewAction, str]:
    if _short_setup(eight_hour) or _short_setup(four_hour):
        return TradingViewAction.REDUCE, "8h/4h conflict against long; reduce until regime confirms"
    if _short_setup(one_hour):
        return TradingViewAction.REDUCE, "1h timing is against unconfirmed long; reduce exposure"
    if _short_setup(five_minute) or five_minute.btc_fast_bear:
        return TradingViewAction.REDUCE, "5m early warning is against unconfirmed long; reduce exposure"
    return TradingViewAction.HOLD, "unconfirmed long is not hostile enough to reduce"


def _unconfirmed_short_action(
    eight_hour: _TimeframeFlags,
    four_hour: _TimeframeFlags,
    one_hour: _TimeframeFlags,
    five_minute: _TimeframeFlags,
) -> tuple[TradingViewAction, str]:
    if _core_long(eight_hour) or _core_long(four_hour):
        return TradingViewAction.REDUCE, "8h/4h conflict against short; reduce until regime confirms"
    if _core_long(one_hour):
        return TradingViewAction.REDUCE, "1h timing is against unconfirmed short; reduce exposure"
    if _core_long(five_minute) or five_minute.btc_fast_bull:
        return TradingViewAction.REDUCE, "5m early warning is against unconfirmed short; reduce exposure"
    return TradingViewAction.HOLD, "unconfirmed short is not hostile enough to reduce"


def _long_timing_action(
    one_hour: _TimeframeFlags,
    five_minute: _TimeframeFlags,
) -> tuple[TradingViewAction, str]:
    if _core_long(one_hour):
        return TradingViewAction.ENTER, "1h timing is aligned for long entry/rebalance"
    if _short_setup(one_hour):
        return TradingViewAction.REDUCE, "1h timing is against long exposure; reduce instead of flipping"
    if _short_setup(five_minute) or five_minute.btc_fast_bear:
        return TradingViewAction.REDUCE, "1h timing is mixed and 5m is against long; reduce early"
    return TradingViewAction.HOLD, "1h timing is mixed; hold current exposure"


def _short_timing_action(
    one_hour: _TimeframeFlags,
    five_minute: _TimeframeFlags,
) -> tuple[TradingViewAction, str]:
    if _short_setup(one_hour):
        return TradingViewAction.ENTER, "1h timing is aligned for short entry/rebalance"
    if _core_long(one_hour):
        return TradingViewAction.REDUCE, "1h timing is against short exposure; reduce instead of flipping"
    if _core_long(five_minute) or five_minute.btc_fast_bull:
        return TradingViewAction.REDUCE, "1h timing is mixed and 5m is against short; reduce early"
    return TradingViewAction.HOLD, "1h timing is mixed; hold current exposure"


def tradingview_flag_score(alert: TradingViewAlert) -> float:
    score = 0.0
    score += _flag_pair_score(alert.btc_up, alert.btc_down, 40.0)
    score += _flag_pair_score(alert.total_up, alert.total_down, 25.0)
    score += _flag_pair_score(alert.total2_up, alert.total2_down, 25.0)

    if alert.btcd_down is True:
        score += 10.0
    elif alert.btcd_up:
        score -= 10.0

    return score


def tradingview_decision_reason(alert: TradingViewAlert, regime: TradingViewRegime) -> str:
    if regime == TradingViewRegime.TOP10_LONG:
        if alert.btcd_up:
            return "Server entry: BTC, TOTAL, TOTAL2 up; diversified TOP10 with reduced leverage because BTC.D is up"
        return "Server entry: BTC, TOTAL, TOTAL2 up with BTC.D down"
    if regime == TradingViewRegime.BTC_ETH_LONG:
        return "Server entry: BTC/TOTAL up, TOTAL2 lagging, BTC.D up"
    if regime == TradingViewRegime.ALT_WEAK_SHORT:
        return "Server entry: BTC down, TOTAL3 weak, BTC.D up"
    if regime == TradingViewRegime.SHORT_MODE:
        return "Server entry: BTC, TOTAL, TOTAL2 down"

    if alert.btc_up and alert.total_up and alert.total2_up:
        return "TOP10 needs BTC.D confirmation"
    if alert.btc_up and alert.total_up and not alert.total2_up and not alert.btcd_up:
        return "BTC/ETH needs BTC.D up"
    if alert.btc_up and alert.total_up:
        return "mixed long filters"

    if alert.btc_down is True and alert.total_down is True and alert.total2_down is not True:
        return "SHORT needs TOTAL2 down"
    if alert.btc_down is True and alert.total3_weak and not alert.btcd_up:
        return "ALT short needs BTC.D up"

    return "Server range filters"


def _probe_entries_enabled() -> bool:
    return os.environ.get("ENGINE_TV_ALLOW_PROBE_ENTRIES", "").lower() == "true"


def _probe_entry_leverage(max_leverage: float) -> float:
    try:
        leverage = float(os.environ.get("ENGINE_TV_PROBE_LEVERAGE", "0.5"))
    except ValueError:
        leverage = 0.5
    return max(0.0, min(leverage, max_leverage))


def _flag_pair_score(up: bool | None, down: bool | None, weight: float) -> float:
    if up is True and down is not True:
        return weight
    if down is True and up is not True:
        return -weight
    return 0.0


class TradingViewAlertGate:
    def __init__(self) -> None:
        self._seen: set[str] = set()

    def accept(self, alert: TradingViewAlert, **validate_kwargs: Any) -> tuple[bool, tuple[str, ...]]:
        errors = list(alert.validate(**validate_kwargs))
        key = alert.dedupe_key()
        if key in self._seen:
            errors.append("duplicate TradingView alert")
        if errors:
            return False, tuple(errors)
        self._seen.add(key)
        return True, tuple()
