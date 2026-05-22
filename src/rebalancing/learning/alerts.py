from __future__ import annotations

import json
import logging
import os
from typing import Any, Mapping
from urllib.parse import urlencode
from urllib.request import Request, urlopen


logger = logging.getLogger(__name__)


def notify_learning_result(result: Mapping[str, Any]) -> bool:
    token = os.environ.get("TELEGRAM_BOT_TOKEN") or os.environ.get("LEARNING_TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID") or os.environ.get("LEARNING_TELEGRAM_CHAT_ID")
    if not token or not chat_id:
        return False

    text = learning_result_message(result)
    request = Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=urlencode({"chat_id": chat_id, "text": text}).encode("utf-8"),
        headers={"content-type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=_env_float("TELEGRAM_TIMEOUT_SECONDS", 10.0)) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return bool(payload.get("ok"))
    except Exception as exc:
        logger.warning("Telegram learning notification failed: %s", exc)
        return False


def learning_result_message(result: Mapping[str, Any]) -> str:
    status = result.get("status", "unknown")
    evaluation_id = result.get("evaluation_id")
    stage_before = result.get("stage_before")
    stage_after = result.get("stage_after")
    promoted = "yes" if result.get("promoted") else "no"
    apply_result = result.get("apply_result") if isinstance(result.get("apply_result"), Mapping) else {}
    version = apply_result.get("version")
    active = apply_result.get("active")
    accepted = apply_result.get("accepted") if isinstance(apply_result.get("accepted"), list) else []
    changed = ", ".join(str(item.get("name")) for item in accepted[:6] if isinstance(item, Mapping)) or "none"
    error = result.get("error")

    lines = [
        "[Rebalancing Learning]",
        f"status: {status}",
        f"evaluation: {evaluation_id}",
        f"params version: {version} active={active}",
        f"changed: {changed}",
        f"stage: {stage_before} -> {stage_after} promoted={promoted}",
    ]
    if error:
        lines.append(f"error: {error}")
    return "\n".join(lines)


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, str(default)))
    except ValueError:
        return default
