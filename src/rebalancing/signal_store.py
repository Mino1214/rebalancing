from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from .tradingview import (
    TradingViewAlert,
    TradingViewAlertError,
    TradingViewServerDecision,
    finalize_tradingview_alert,
)


DEFAULT_MAX_RECORDS = 200


def expected_engine_webhook_token() -> str | None:
    token = os.environ.get("ENGINE_WEBHOOK_TOKEN", "").strip()
    if token:
        return token

    path = engine_webhook_token_path()
    try:
        return path.read_text(encoding="utf-8").strip() or None
    except FileNotFoundError:
        return None


def expected_tradingview_passphrase() -> str | None:
    token = os.environ.get("TV_WEBHOOK_PASSPHRASE", "").strip()
    if token:
        return token

    path_value = os.environ.get("TV_WEBHOOK_PASSPHRASE_FILE", "").strip()
    if not path_value:
        return None
    try:
        return Path(path_value).read_text(encoding="utf-8").strip() or None
    except FileNotFoundError:
        return None


def engine_webhook_token_path() -> Path:
    return Path(os.environ.get("ENGINE_WEBHOOK_TOKEN_FILE", _state_dir() / "engine_webhook_token"))


def signal_store_path() -> Path:
    return Path(os.environ.get("ENGINE_SIGNAL_STORE_PATH", _state_dir() / "tradingview_alerts.json"))


def record_tradingview_alert(
    payload: Mapping[str, Any],
    *,
    path: Path | None = None,
    max_records: int | None = None,
) -> tuple[dict[str, Any], bool]:
    sanitized = dict(payload)
    sanitized.pop("passphrase", None)
    alert = TradingViewAlert.parse(sanitized)
    max_leverage = _env_float("ENGINE_TV_MAX_LEVERAGE", 2.0)
    max_age_seconds = _optional_env_int("ENGINE_TV_MAX_ALERT_AGE_SECONDS")
    errors = alert.validate(
        max_leverage=max_leverage,
        max_age_seconds=max_age_seconds,
        enforce_target_leverage=False,
        validate_regime_consistency=False,
    )
    if errors:
        raise TradingViewAlertError("; ".join(errors))

    alert, decision = finalize_tradingview_alert(alert, max_leverage=max_leverage)
    record = _alert_record(alert, sanitized, decision)
    path = path or signal_store_path()
    max_records = max_records or _env_int("ENGINE_SIGNAL_STORE_MAX_RECORDS", DEFAULT_MAX_RECORDS)
    records = _read_records(path)

    for existing in records:
        if existing.get("signal_id") == record["signal_id"]:
            return existing, True

    records.append(record)
    records = records[-max_records:]
    _write_records(path, records)
    return record, False


def latest_tradingview_alert(*, path: Path | None = None) -> dict[str, Any] | None:
    records = recent_tradingview_alerts(limit=1, path=path)
    return records[0] if records else None


def recent_tradingview_alerts(*, limit: int = 20, path: Path | None = None) -> list[dict[str, Any]]:
    records = _read_records(path or signal_store_path())
    records = sorted(records, key=lambda item: int(item.get("received_at_ms") or 0), reverse=True)
    return records[:limit]


def tradingview_alert_events(*, limit: int = 10, path: Path | None = None) -> list[dict[str, str]]:
    return [_event_from_record(record) for record in recent_tradingview_alerts(limit=limit, path=path)]


def _alert_record(
    alert: TradingViewAlert,
    payload: Mapping[str, Any],
    decision: TradingViewServerDecision,
) -> dict[str, Any]:
    received_at_ms = _int_or_now(payload.get("received_at_ms"))
    forwarded_at_ms = _optional_int(payload.get("forwarded_at_ms"))
    return {
        "schema": alert.schema,
        "source": alert.source,
        "decision_source": "server",
        "decision_action": decision.action.value,
        "decision_reason": decision.reason,
        "source_regime": decision.source_regime.value,
        "source_target_leverage": decision.source_target_leverage,
        "regime": alert.regime.value,
        "target_leverage": alert.target_leverage,
        "score": decision.score,
        "btc_up": alert.btc_up,
        "btc_down": alert.btc_down,
        "btc_fast_bull": alert.btc_fast_bull,
        "btc_fast_bear": alert.btc_fast_bear,
        "total_up": alert.total_up,
        "total_down": alert.total_down,
        "total2_up": alert.total2_up,
        "total2_down": alert.total2_down,
        "total3_up": alert.total3_up,
        "total3_weak": alert.total3_weak,
        "btcd_up": alert.btcd_up,
        "btcd_down": alert.btcd_down,
        "tf": alert.tf,
        "confirmed": alert.confirmed,
        "time_ms": alert.time_ms,
        "bar_time_ms": alert.bar_time_ms,
        "signal_id": alert.dedupe_key(),
        "received_at_ms": received_at_ms,
        "forwarded_at_ms": forwarded_at_ms,
        **({"timeframes": dict(alert.timeframes)} if alert.timeframes else {}),
    }


def _event_from_record(record: Mapping[str, Any]) -> dict[str, str]:
    regime = str(record.get("regime", "-"))
    tf = str(record.get("tf") or "-")
    leverage = record.get("target_leverage", 0)
    action = str(record.get("decision_action") or "ENTER")
    signal_id = str(record.get("signal_id", "-"))
    short_id = signal_id if len(signal_id) <= 32 else f"{signal_id[:29]}..."
    return {
        "time": _iso_from_ms(_int_or_now(record.get("received_at_ms"))),
        "kind": "ALERT",
        "message": f"TradingView {regime} {action} tf={tf} leverage={leverage} accepted ({short_id})",
    }


def _read_records(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return []
    except json.JSONDecodeError:
        return []

    if not isinstance(data, list):
        return []
    return [dict(item) for item in data if isinstance(item, dict)]


def _write_records(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(records, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
        temp_name = handle.name
    Path(temp_name).replace(path)


def _state_dir() -> Path:
    return Path(os.environ.get("ENGINE_STATE_DIR", ".state"))


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


def _optional_env_int(name: str) -> int | None:
    value = os.environ.get(name)
    if not value:
        return None
    try:
        parsed = int(value)
    except ValueError:
        return None
    return parsed if parsed > 0 else None


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _int_or_now(value: Any) -> int:
    parsed = _optional_int(value)
    if parsed is not None:
        return parsed
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def _iso_from_ms(value: int) -> str:
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc).isoformat(timespec="seconds")
