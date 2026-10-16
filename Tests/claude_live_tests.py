"""Tests for scripts/claude_live.py. Run with: python3 -m unittest discover -s Tests -p '*_tests.py'"""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "claude_live.py"
spec = importlib.util.spec_from_file_location("claude_live", SCRIPT)
claude_live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(claude_live)

NOW = 1_792_160_000.0


class ParsingTests(unittest.TestCase):
    def test_usage_response(self):
        payload = {
            "five_hour": {"utilization": 43.0, "resets_at": "2026-10-16T18:10:00.198648+00:00"},
            "seven_day": {"utilization": 15.0, "resets_at": "2026-10-21T10:00:00+00:00"},
        }
        reading = claude_live.parse_usage_response(payload, NOW)
        self.assertEqual(reading["claude_5h"], 43.0)
        self.assertEqual(reading["claude_7d"], 15.0)
        self.assertEqual(reading["claude_5h_resets_at"], 1792174200)
        self.assertEqual(reading["claude_7d_resets_at"], 1792576800)
        self.assertEqual(reading["claude_source"], "claude-code-oauth-usage")
        self.assertEqual(reading["claude_data_at"], int(NOW))

    def test_usage_response_without_windows_is_rejected(self):
        self.assertIsNone(claude_live.parse_usage_response({"five_hour": None}, NOW))
        self.assertIsNone(claude_live.parse_usage_response([], NOW))

    def test_out_of_range_percentages_are_dropped(self):
        payload = {"five_hour": {"utilization": 140}, "seven_day": {"utilization": True}}
        self.assertIsNone(claude_live.parse_usage_response(payload, NOW))

    def test_desktop_history_uses_latest_sample_in_milliseconds(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            path.write_text(json.dumps({"version": 2, "samples": [
                {"t": 1792160089993, "u": {"fh": 15, "sd": 13}},
                {"t": 1792156541574, "u": {"fh": 0, "sd": 12}},
            ]}))
            reading = claude_live.desktop_reading(path)
        self.assertEqual(reading["claude_5h"], 15)
        self.assertEqual(reading["claude_data_at"], 1792160089)
        self.assertIsNone(reading["claude_5h_resets_at"])

    def test_statusline_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "claude.json"
            path.write_text(json.dumps({
                "rate_limits": {"five_hour": {"used_percentage": 49.9, "resets_at": 1792169100},
                                "seven_day": {"used_percentage": 81.2, "resets_at": 1792255500}},
                "captured_at": "2026-10-16T13:04:02Z",
            }))
            reading = claude_live.statusline_reading(path)
        self.assertEqual(reading["claude_7d"], 81.2)
        self.assertEqual(reading["claude_5h_resets_at"], 1792169100)
        self.assertEqual(reading["claude_source"], "claude-code-statusline")


class MergeTests(unittest.TestCase):
    def live(self, at=NOW, five=43.0):
        return claude_live.reading("claude-code-oauth-usage", five, 15.0, NOW + 3600, NOW + 86400, at)

    def test_merge_keeps_other_fields_and_recomputes_mood(self):
        status = {"codex_7d": 3.0, "codex_data_at": "x", "claude_5h": 15.0, "mood": "happy",
                  "level": "ok", "claude_data_at": "2026-10-16T13:14:49Z"}
        merged = claude_live.merge_status(status, self.live(five=92.0), NOW)
        self.assertEqual(merged["codex_7d"], 3.0)
        self.assertEqual(merged["codex_data_at"], "x")
        self.assertEqual(merged["claude_5h"], 92.0)
        self.assertEqual((merged["level"], merged["mood"]), ("crit", "panic"))
        self.assertEqual(merged["claude_source"], "claude-code-oauth-usage")
        self.assertEqual(merged["updated_at"], claude_live.iso(NOW))

    def test_merge_never_replaces_newer_claude_data(self):
        status = {"claude_data_at": claude_live.iso(NOW + 60)}
        self.assertIsNone(claude_live.merge_status(status, self.live(), NOW))

    def test_merge_ignores_very_old_readings(self):
        self.assertIsNone(claude_live.merge_status({}, self.live(at=NOW - 7 * 3600), NOW))

    def test_levels(self):
        self.assertEqual(claude_live.level_for([10, None, 69.9]), ("ok", "happy"))
        self.assertEqual(claude_live.level_for([70]), ("warn", "worried"))
        self.assertEqual(claude_live.level_for([90]), ("crit", "panic"))
        self.assertEqual(claude_live.level_for([None]), (None, None))


class RunTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.env = {"USAGE_WATCHER_DIR": self.directory.name, "HOME": self.directory.name}
        self.saved = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)
        self.path = Path(self.directory.name)

    def tearDown(self):
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.directory.cleanup()

    def test_success_creates_status_file(self):
        live = claude_live.reading("claude-code-oauth-usage", 43.0, 15.0, None, None, NOW)
        best, error = claude_live.run(fetch=lambda: live, at=NOW)
        self.assertIsNone(error)
        status = json.loads((self.path / "status.json").read_text())
        self.assertEqual(status["claude_5h"], 43.0)
        self.assertEqual(oct((self.path / "status.json").stat().st_mode & 0o777), "0o600")

    def test_failure_keeps_last_reading_and_backs_off(self):
        live = claude_live.reading("claude-code-oauth-usage", 43.0, 15.0, None, None, NOW)
        claude_live.run(fetch=lambda: live, at=NOW)

        def failing():
            raise claude_live.FetchError("usage endpoint returned HTTP 429", NOW + 300)

        best, error = claude_live.run(fetch=failing, at=NOW + 60)
        self.assertEqual(best["claude_5h"], 43.0)
        self.assertIn("429", error)
        state = json.loads((self.path / "claude_live.json").read_text())
        self.assertEqual(state["retry_at"], int(NOW + 300))

        def unexpected():
            raise AssertionError("must not fetch during back-off")

        claude_live.run(fetch=unexpected, at=NOW + 120)

    def test_falls_back_to_desktop_history(self):
        desktop = self.path / "Library" / "Application Support" / "Claude"
        desktop.mkdir(parents=True)
        (desktop / "plan-usage-history.json").write_text(json.dumps(
            {"samples": [{"t": (NOW - 60) * 1000, "u": {"fh": 15, "sd": 13}}]}))

        def failing():
            raise claude_live.FetchError("offline")

        best, _ = claude_live.run(fetch=failing, at=NOW)
        self.assertEqual(best["claude_source"], "claude-desktop-app")
        self.assertEqual(json.loads((self.path / "status.json").read_text())["claude_5h"], 15)


if __name__ == "__main__":
    unittest.main()
