from __future__ import annotations

import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from .status import build_status_payload, payload_to_json


class StatusHandler(BaseHTTPRequestHandler):
    server_version = "RebalancingStatus/0.1"

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
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")


def run() -> None:
    host = os.environ.get("ENGINE_HOST", "127.0.0.1")
    port = int(os.environ.get("ENGINE_PORT", "8788"))
    server = ThreadingHTTPServer((host, port), StatusHandler)
    print(f"status API listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    run()
