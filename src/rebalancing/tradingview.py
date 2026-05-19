from __future__ import annotations

import json
from dataclasses import dataclass, field
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


class TradingViewAlertError(ValueError):
    pass


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
    btc_down: bool | None = None
    total_down: bool | None = None
    total2_down: bool | None = None
    total3_up: bool | None = None
    btcd_down: bool | None = None
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
                btc_down=cls._optional_bool(data.get("btc_down"), "btc_down"),
                total_down=cls._optional_bool(data.get("total_down"), "total_down"),
                total2_down=cls._optional_bool(data.get("total2_down"), "total2_down"),
                total3_up=cls._optional_bool(data.get("total3_up"), "total3_up"),
                btcd_down=cls._optional_bool(data.get("btcd_down"), "btcd_down"),
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
    ) -> tuple[str, ...]:
        errors: list[str] = []

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

        errors.extend(self._consistency_errors())
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

    def dedupe_key(self) -> str:
        if self.signal_id:
            return self.signal_id
        bar_time = self.bar_time_ms if self.bar_time_ms is not None else self.time_ms
        return f"{self.schema}:{self.tf or 'unknown'}:{bar_time}:{self.regime}"

    def _consistency_errors(self) -> tuple[str, ...]:
        errors: list[str] = []
        if self.btc_down is not None and self.btc_up and self.btc_down:
            errors.append("btc_up and btc_down cannot both be true")
        if self.total_down is not None and self.total_up and self.total_down:
            errors.append("total_up and total_down cannot both be true")
        if self.total2_down is not None and self.total2_up and self.total2_down:
            errors.append("total2_up and total2_down cannot both be true")
        if self.total3_up is not None and self.total3_up and self.total3_weak:
            errors.append("total3_up and total3_weak cannot both be true")
        if self.btcd_down is not None and self.btcd_up and self.btcd_down:
            errors.append("btcd_up and btcd_down cannot both be true")

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

