"""Tests for the credential-free Codex app-server rate limit helper."""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "codex_live.py"
spec = importlib.util.spec_from_file_location("codex_live", SCRIPT)
codex_live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codex_live)

NOW = 1_792_160_000.0
RESET = 1_792_655_962


class CodexLiveTests(unittest.TestCase):
    def payload(self, value=3, reset=RESET):
        return {"rateLimitsByLimitId": {"codex": {
            "primary": {"usedPercent": value, "windowDurationMins": 10080, "resetsAt": reset},
            "secondary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": NOW + 3000},
        }}}

    def test_prefers_weekly_codex_bucket_and_keeps_reset(self):
        result = codex_live.parse_response(self.payload(), NOW)
        self.assertEqual(result["codex_7d"], 3.0)
        self.assertEqual(result["codex_5h"], 12.0)
        self.assertEqual(result["codex_7d_resets_at"], RESET)
        self.assertEqual(result["codex_source"], "codex-app-server")
        self.assertEqual(result["codex_data_at"], codex_live.iso(NOW))

    def test_rejects_missing_or_invalid_windows(self):
        self.assertIsNone(codex_live.parse_response({}, NOW))
        self.assertIsNone(codex_live.parse_response({"rateLimits": {
            "primary": {"usedPercent": True}}}, NOW))
        self.assertIsNone(codex_live.parse_response({"rateLimits": {
            "primary": {"usedPercent": 101}}}, NOW))
        self.assertIsNone(codex_live.parse_response({"rateLimits": {
            "primary": {"usedPercent": 40, "windowDurationMins": 300}}}, NOW))

    def test_merge_preserves_claude_and_uses_peak(self):
        status = {"claude_5h": 68, "claude_data_at": "2026-10-16T13:00:00Z",
                  "claude_source": "claude-code-oauth-usage", "level": "ok", "mood": "happy"}
        merged = codex_live.merge_status(status, codex_live.parse_response(self.payload(), NOW), NOW)
        self.assertEqual(merged["claude_5h"], 68)
        self.assertEqual(merged["claude_data_at"], status["claude_data_at"])
        self.assertEqual(merged["claude_source"], status["claude_source"])
        self.assertEqual((merged["level"], merged["mood"]), ("warn", "worried"))
        self.assertEqual(merged["codex_7d"], 3)

    def test_forecast_requires_same_window_and_five_minutes(self):
        self.assertTrue(codex_live.forecast_100(40, NOW - 600, RESET, 42, NOW, RESET))
        self.assertFalse(codex_live.forecast_100(40, NOW - 60, RESET, 42, NOW, RESET))
        self.assertTrue(codex_live.forecast_100(40, NOW - 600, RESET - 1, 42, NOW, RESET))
        self.assertFalse(codex_live.forecast_100(40, NOW - 600, RESET - 10, 42, NOW, RESET))
        self.assertFalse(codex_live.forecast_100(42, NOW - 600, RESET, 40, NOW, RESET))

    def test_run_writes_only_codex_fields_and_mode_600(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = os.environ.get("USAGE_WATCHER_DIR")
            os.environ["USAGE_WATCHER_DIR"] = directory
            try:
                path = Path(directory) / "status.json"
                path.write_text(json.dumps({"claude_5h": 68, "claude_7d": 16,
                                            "claude_data_at": "2026-10-16T13:00:00Z"}))
                codex_live.run(fetch=lambda: self.payload(), at=NOW)
                result = json.loads(path.read_text())
                self.assertEqual(result["claude_5h"], 68)
                self.assertEqual(result["codex_7d"], 3)
                self.assertEqual(result["mood"], "worried")
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            finally:
                if previous is None:
                    os.environ.pop("USAGE_WATCHER_DIR")
                else:
                    os.environ["USAGE_WATCHER_DIR"] = previous


if __name__ == "__main__":
    unittest.main()
