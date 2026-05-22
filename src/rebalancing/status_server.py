from __future__ import annotations

import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from typing import Any, Mapping
from urllib.parse import urlparse

from .paper import paper_trading_enabled, process_paper_alert
from .signal_store import (
    expected_engine_webhook_token,
    expected_tradingview_passphrase,
    record_tradingview_alert,
)
from .status import build_status_payload, payload_to_json
from .tradingview import TradingViewAlertError


class StatusHandler(BaseHTTPRequestHandler):
    server_version = "RebalancingStatus/0.1"
    max_body_bytes = 64 * 1024

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json({"ok": True})
            return

        if parsed.path == "/status":
            try:
                self._json(build_status_payload())
            except Exception as exc:
                self._json({"ok": False, "error": str(exc)}, status=500)
            return

        self._json({"ok": False, "error": "not_found"}, status=404)

    def do_HEAD(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path in {"/health", "/status"}:
            self.send_response(200)
            self._cors_headers()
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return

        self.send_response(404)
        self._cors_headers()
        self.end_headers()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/webhook/tradingview":
            self._json({"ok": False, "error": "not_found"}, status=404)
            return

        try:
            payload = self._read_json_body()
            if not self._authorized(payload):
                self._json({"ok": False, "error": "unauthorized"}, status=401)
                return
            record, duplicate = record_tradingview_alert(payload)
            if paper_trading_enabled() and not duplicate:
                Thread(target=_process_paper_alert, args=(payload,), daemon=True).start()
        except ValueError as exc:
            self._json({"ok": False, "error": "bad_request", "details": str(exc)}, status=400)
            return
        except TradingViewAlertError as exc:
            self._json({"ok": False, "error": "invalid_alert", "details": str(exc)}, status=400)
            return
        except Exception as exc:
            self._json({"ok": False, "error": "store_failed", "details": str(exc)}, status=500)
            return

        self._json(
            {
                "ok": True,
                "accepted": not duplicate,
                "duplicate": duplicate,
                "signal_id": record["signal_id"],
                "regime": record["regime"],
                "target_leverage": record["target_leverage"],
                "score": record.get("score"),
                "decision_action": record.get("decision_action"),
                "decision_reason": record.get("decision_reason"),
            },
            status=200 if duplicate else 202,
        )

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        if os.environ.get("ENGINE_ACCESS_LOG", "").lower() == "true":
            super().log_message(format, *args)

    def _json(self, payload: dict, *, status: int = 200) -> None:
        body = payload_to_json(payload).encode("utf-8")
        self.send_response(status)
        self._cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", os.environ.get("ENGINE_CORS_ORIGIN", "*"))
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Engine-Token")

    def _authorized(self, payload: Mapping[str, Any]) -> bool:
        return webhook_authorized(self.headers, payload)

    def _read_json_body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("invalid Content-Length") from exc
        if length <= 0:
            raise ValueError("empty request body")
        if length > self.max_body_bytes:
            raise ValueError("request body too large")

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid JSON body") from exc
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload


def run() -> None:
    host = os.environ.get("ENGINE_HOST", "127.0.0.1")
    port = int(os.environ.get("ENGINE_PORT", "8788"))
    _start_learning_scheduler()
    server = ThreadingHTTPServer((host, port), StatusHandler)
    print(f"status API listening on http://{host}:{port}")
    server.serve_forever()


def webhook_authorized(headers: Mapping[str, str], payload: Mapping[str, Any]) -> bool:
    expected_engine_token = expected_engine_webhook_token()
    if expected_engine_token:
        provided_engine_token = headers.get("X-Engine-Token", "")
        if hmac.compare_digest(str(provided_engine_token), expected_engine_token):
            return True

    expected_passphrase = expected_tradingview_passphrase()
    if expected_passphrase:
        provided_passphrase = payload.get("passphrase", "")
        if hmac.compare_digest(str(provided_passphrase), expected_passphrase):
            return True

    return False


def _process_paper_alert(payload: dict) -> None:
    try:
        process_paper_alert(payload)
    except Exception as exc:
        if os.environ.get("ENGINE_ACCESS_LOG", "").lower() == "true":
            print(f"paper processing failed: {exc}")


def _start_learning_scheduler() -> None:
    if os.environ.get("LEARNING_BACKGROUND_ENABLED", "").lower() != "true":
        return

    def run_background() -> None:
        from .learning.loop import run_scheduler

        interval = _env_int("LEARNING_INTERVAL_SECONDS", 600)
        window = _env_int("LEARNING_WINDOW", 100)
        mode = os.environ.get("LEARNING_MODE", "paper") or None
        run_scheduler(window=window, mode=mode, interval_seconds=interval)

    Thread(target=run_background, daemon=True).start()


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


if __name__ == "__main__":
    run()
