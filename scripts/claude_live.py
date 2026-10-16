#!/usr/bin/env python3
"""Keep Claude plan usage in ~/.usage-watcher current for LimitNotch.

Run every ~60 seconds by a LaunchAgent. Sources, best first:

1. claude-code-oauth-usage: GET https://api.anthropic.com/api/oauth/usage, the endpoint behind
   Claude Code's /usage, authenticated with the OAuth token Claude Code already stores (macOS
   Keychain item "Claude Code-credentials", or ~/.claude/.credentials.json). The token is only
   sent to api.anthropic.com; it is never logged, written or refreshed here.
2. claude-code-statusline: rate_limits saved by a Claude Code status line in
   ~/.usage-watcher/claude.json.
3. claude-desktop-app: the Claude desktop app's plan-usage-history.json (no reset times).

The freshest reading wins. It is written to ~/.usage-watcher/claude_live.json and merged into the
claude_* fields of ~/.usage-watcher/status.json, leaving the other fields alone.
"""

import json
import fcntl
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
KEYCHAIN_SERVICE = "Claude Code-credentials"
USER_AGENT = "LimitNotch-claude-live/1.0"
# Readings older than this are not merged into status.json.
MAX_AGE = 6 * 3600
MAX_BACKOFF = 15 * 60


def home():
    return Path(os.environ.get("HOME") or Path.home())


def watcher_dir():
    configured = os.environ.get("USAGE_WATCHER_DIR")
    return Path(configured).expanduser() if configured else home() / ".usage-watcher"


def now():
    return time.time()


def iso(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_time(value):
    """Unix seconds (or milliseconds) or an ISO 8601 string to Unix seconds."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        seconds = float(value)
        if seconds > 100_000_000_000:
            seconds /= 1000
        return seconds if seconds > 0 else None
    if isinstance(value, str) and value.strip():
        text = value.strip().replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(text).timestamp()
        except ValueError:
            return None
    return None


def percent(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if 0 <= value <= 100 else None


def reading(source, five, seven, five_reset, seven_reset, data_at):
    if five is None and seven is None:
        return None
    return {
        "claude_5h": five,
        "claude_7d": seven,
        "claude_5h_resets_at": int(five_reset) if five_reset else None,
        "claude_7d_resets_at": int(seven_reset) if seven_reset else None,
        "claude_data_at": int(data_at),
        "claude_source": source,
    }


# MARK: - OAuth usage endpoint

def config_dir():
    configured = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(configured).expanduser() if configured else home() / ".claude"


def access_token():
    """Claude Code's OAuth access token, or None. Expired tokens are skipped, never refreshed."""
    blobs = []
    if sys.platform == "darwin":
        try:
            result = subprocess.run(
                ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                blobs.append(result.stdout)
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        blobs.append((config_dir() / ".credentials.json").read_text(encoding="utf-8"))
    except OSError:
        pass
    for blob in blobs:
        try:
            oauth = json.loads(blob).get("claudeAiOauth") or {}
        except (ValueError, AttributeError):
            continue
        token = oauth.get("accessToken")
        expires = parse_time(oauth.get("expiresAt"))
        if isinstance(token, str) and token and (expires is None or expires > now() + 30):
            return token
    return None


def parse_usage_response(payload, fetched_at):
    if not isinstance(payload, dict):
        return None
    five = payload.get("five_hour") if isinstance(payload.get("five_hour"), dict) else {}
    seven = payload.get("seven_day") if isinstance(payload.get("seven_day"), dict) else {}
    return reading(
        "claude-code-oauth-usage",
        percent(five.get("utilization")),
        percent(seven.get("utilization")),
        parse_time(five.get("resets_at")),
        parse_time(seven.get("resets_at")),
        fetched_at,
    )


class FetchError(Exception):
    def __init__(self, message, retry_after=None):
        super().__init__(message)
        self.retry_after = retry_after


def fetch_oauth_usage():
    token = access_token()
    if token is None:
        raise FetchError("no valid Claude Code login (run `claude` once to sign in or refresh)")
    request = urllib.request.Request(USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    })
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        retry = None
        try:
            retry = now() + float(error.headers.get("retry-after", ""))
        except (AttributeError, TypeError, ValueError):
            pass
        raise FetchError(f"usage endpoint returned HTTP {error.code}", retry) from None
    except (urllib.error.URLError, OSError, ValueError) as error:
        raise FetchError(f"usage endpoint unreachable: {type(error).__name__}") from None
    result = parse_usage_response(payload, now())
    if result is None:
        raise FetchError("usage endpoint returned no five_hour/seven_day data")
    return result


# MARK: - Local fallbacks

def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def statusline_reading(path):
    snapshot = read_json(path)
    if not isinstance(snapshot, dict):
        return None
    limits = snapshot.get("rate_limits") if isinstance(snapshot.get("rate_limits"), dict) else {}
    five = limits.get("five_hour") if isinstance(limits.get("five_hour"), dict) else {}
    seven = limits.get("seven_day") if isinstance(limits.get("seven_day"), dict) else {}
    captured = parse_time(snapshot.get("captured_at"))
    if captured is None:
        return None
    return reading(
        "claude-code-statusline",
        percent(five.get("used_percentage")),
        percent(seven.get("used_percentage")),
        parse_time(five.get("resets_at")),
        parse_time(seven.get("resets_at")),
        captured,
    )


def desktop_reading(path):
    history = read_json(path)
    samples = history.get("samples") if isinstance(history, dict) else None
    if not isinstance(samples, list):
        return None
    latest = None
    for sample in samples:
        if not isinstance(sample, dict) or not isinstance(sample.get("u"), dict):
            continue
        at = parse_time(sample.get("t"))
        if at is not None and (latest is None or at > latest[0]):
            latest = (at, sample["u"])
    if latest is None:
        return None
    at, usage = latest
    return reading("claude-desktop-app", percent(usage.get("fh")), percent(usage.get("sd")), None, None, at)


def desktop_history_path():
    return home() / "Library" / "Application Support" / "Claude" / "plan-usage-history.json"


def freshest(*candidates):
    valid = [c for c in candidates if c and c.get("claude_data_at")]
    return max(valid, key=lambda c: c["claude_data_at"], default=None)


# MARK: - Status file

def level_for(values):
    peak = max((v for v in values if v is not None), default=None)
    if peak is None:
        return None, None
    if peak >= 85:
        return "crit", "panic"
    if peak >= 60:
        return "warn", "worried"
    return "ok", "happy"


def note_for(status):
    def shown(value):
        return "—" if value is None else f"{round(value)}%"
    parts = [f"Claude 5h {shown(status.get('claude_5h'))}, weekly {shown(status.get('claude_7d'))}"]
    if status.get("codex_7d") is not None:
        parts.append(f"Codex weekly {shown(status.get('codex_7d'))}")
    return "; ".join(parts) + "."


CLAUDE_KEYS = ("claude_5h", "claude_7d", "claude_5h_resets_at", "claude_7d_resets_at",
               "claude_data_at", "claude_source")


def merge_status(status, live, at):
    """Return status.json with the live Claude reading applied, or None if nothing changes."""
    status = dict(status) if isinstance(status, dict) else {}
    if not live or at - live["claude_data_at"] > MAX_AGE:
        return None
    existing = parse_time(status.get("claude_data_at"))
    if existing is not None and existing > live["claude_data_at"]:
        return None
    for prefix, value_key, reset_key in (
        ("claude_5h", "claude_5h", "claude_5h_resets_at"),
        ("claude_7d", "claude_7d", "claude_7d_resets_at"),
    ):
        old_value, new_value = status.get(value_key), live.get(value_key)
        old_reset, new_reset = status.get(reset_key), live.get(reset_key)
        elapsed = live["claude_data_at"] - existing if existing is not None else 0
        status[prefix + "_forecast_100"] = bool(
            isinstance(old_value, (int, float)) and not isinstance(old_value, bool)
            and isinstance(new_value, (int, float)) and not isinstance(new_value, bool)
            and elapsed >= 300 and isinstance(old_reset, (int, float))
            and isinstance(new_reset, (int, float)) and abs(old_reset - new_reset) <= 5
            and new_reset is not None and new_reset > live["claude_data_at"]
            and new_value > old_value
            and new_value + (new_value - old_value) / elapsed
            * (new_reset - live["claude_data_at"]) >= 100)
    for key in CLAUDE_KEYS:
        status[key] = live.get(key)
    status["claude_data_at"] = iso(live["claude_data_at"])
    level, mood = level_for([status.get("claude_5h"), status.get("claude_7d"),
                             status.get("codex_5h"), status.get("codex_7d")])
    if level == "ok" and any(status.get(key) is True for key in (
            "claude_5h_forecast_100", "claude_7d_forecast_100",
            "codex_5h_forecast_100", "codex_7d_forecast_100")):
        level, mood = "warn", "worried"
    if level:
        status["level"], status["mood"] = level, mood
        status["note"] = note_for(status)
    status["updated_at"] = iso(max(at, live["claude_data_at"]))
    return status


def write_json(path, payload):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent,
                                         prefix=f".{path.stem}-", delete=False)
    try:
        with handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2, allow_nan=False)
            handle.write("\n")
        os.chmod(handle.name, 0o600)
        os.replace(handle.name, path)
    except BaseException:
        try:
            os.unlink(handle.name)
        except FileNotFoundError:
            pass
        raise


# MARK: - Main

def run(fetch=fetch_oauth_usage, at=None, verbose=False):
    at = now() if at is None else at
    directory = watcher_dir()
    live_path = directory / "claude_live.json"
    state = read_json(live_path)
    state = state if isinstance(state, dict) else {}
    previous = state.get("reading") if isinstance(state.get("reading"), dict) else None
    error = None
    fresh = None
    failures = int(state.get("failures") or 0)

    if at >= (state.get("retry_at") or 0):
        try:
            fresh = fetch()
            failures = 0
            state.pop("retry_at", None)
        except FetchError as failure:
            error = str(failure)
            failures += 1
            backoff = min(60 * 2 ** min(failures - 1, 4), MAX_BACKOFF)
            state["retry_at"] = int(max(failure.retry_after or 0, at + backoff))
    else:
        error = state.get("error")

    best = freshest(fresh, previous,
                    statusline_reading(directory / "claude.json"),
                    desktop_reading(desktop_history_path()))
    state.update({"reading": best, "error": error, "failures": failures, "checked_at": iso(at)})
    write_json(live_path, state)

    status_path = directory / "status.json"
    with (directory / ".status.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        merged = merge_status(read_json(status_path), best, at)
        if merged is not None:
            write_json(status_path, merged)

    if verbose:
        print(json.dumps({"reading": best, "error": error}, indent=2))
    return best, error


if __name__ == "__main__":
    run(verbose="--print" in sys.argv[1:])
