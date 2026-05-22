from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from rebalancing.status_server import webhook_authorized


class StatusServerAuthTest(unittest.TestCase):
    def setUp(self) -> None:
        self._old_env = {
            key: os.environ.get(key)
            for key in (
                "ENGINE_WEBHOOK_TOKEN",
                "ENGINE_WEBHOOK_TOKEN_FILE",
                "TV_WEBHOOK_PASSPHRASE",
                "TV_WEBHOOK_PASSPHRASE_FILE",
            )
        }

    def tearDown(self) -> None:
        for key, value in self._old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_authorizes_worker_header_token(self) -> None:
        os.environ["ENGINE_WEBHOOK_TOKEN"] = "engine-secret"
        os.environ.pop("TV_WEBHOOK_PASSPHRASE", None)
        os.environ.pop("TV_WEBHOOK_PASSPHRASE_FILE", None)

        self.assertTrue(webhook_authorized({"X-Engine-Token": "engine-secret"}, {}))
        self.assertFalse(webhook_authorized({"X-Engine-Token": "wrong"}, {}))

    def test_authorizes_direct_tradingview_passphrase(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            passphrase_path = Path(tempdir) / "tv-passphrase"
            passphrase_path.write_text("tv-secret\n", encoding="utf-8")
            os.environ.pop("ENGINE_WEBHOOK_TOKEN", None)
            os.environ.pop("ENGINE_WEBHOOK_TOKEN_FILE", None)
            os.environ["TV_WEBHOOK_PASSPHRASE_FILE"] = str(passphrase_path)

            self.assertTrue(webhook_authorized({}, {"passphrase": "tv-secret"}))
            self.assertFalse(webhook_authorized({}, {"passphrase": "wrong"}))


if __name__ == "__main__":
    unittest.main()
