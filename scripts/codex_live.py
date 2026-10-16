#!/usr/bin/env python3
"""Read account rate limits through the installed Codex app-server, once per minute.

The Codex CLI owns authentication. This helper only exchanges local JSON-RPC messages and
extracts usage percentages and reset timestamps; it never opens Codex credential files.
"""

import fcntl
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


def watcher_dir():
    return Path(os.environ.get("USAGE_WATCHER_DIR") or Path.home() / ".usage-watcher")


def iso(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_time(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass
    return None


def read_json(path):
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_json(path, payload):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent,
                                     prefix=f".{path.stem}-", delete=False) as handle:
        temporary = Path(handle.name)
        json.dump(payload, handle, indent=2, allow_nan=False)
        handle.write("\n")
    try:
        temporary.chmod(0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def rpc_rate_limits(cli=None, timeout=15):
    cli = cli or os.environ.get("CODEX_CLI") or shutil.which("codex")
    if not cli:
        raise RuntimeError("Codex CLI is not installed")
    process = subprocess.Popen([cli, "app-server", "--listen", "stdio://"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
    try:
        def send(message):
            process.stdin.write(json.dumps(message).encode() + b"\n")
            process.stdin.flush()

        def receive(request_id):
            pending = b""
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
                if not ready:
                    break
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    try:
                        message = json.loads(line)
                    except ValueError:
                        continue
                    if message.get("id") == request_id:
                        if "result" not in message:
                            raise RuntimeError("Codex app-server rejected rate limits request")
                        return message["result"]
            raise RuntimeError("Codex app-server timed out")

        send({"id": 1, "method": "initialize", "params": {
            "clientInfo": {"name": "limit_notch", "title": "LimitNotch", "version": "1.0.0"},
            "capabilities": {},
        }})
        receive(1)
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "account/rateLimits/read", "params": {}})
        return receive(2)
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def parse_response(response, at):
    if not isinstance(response, dict):
        return None
    buckets = response.get("rateLimitsByLimitId")
    limits = buckets.get("codex") if isinstance(buckets, dict) else None
    if not isinstance(limits, dict):
        limits = response.get("rateLimits")
    if not isinstance(limits, dict):
        return None
    windows = [limits.get(key) for key in ("primary", "secondary")]
    windows = [window for window in windows if isinstance(window, dict)
               and isinstance(window.get("usedPercent"), (int, float))
               and not isinstance(window.get("usedPercent"), bool)
               and 0 <= window["usedPercent"] <= 100]
    if not windows:
        return None
    weekly = next((window for window in windows if window.get("windowDurationMins") == 10080), None)
    if weekly is None:
        return None
    five_hour = next((window for window in windows if window.get("windowDurationMins") == 300), None)
    return {"codex_5h": float(five_hour["usedPercent"]) if five_hour else None,
            "codex_5h_resets_at": five_hour.get("resetsAt") if five_hour else None,
            "codex_7d": float(weekly["usedPercent"]),
            "codex_7d_resets_at": weekly.get("resetsAt"),
            "codex_data_at": iso(at), "codex_source": "codex-app-server"}


def level_for(status):
    values = [status.get(key) for key in ("claude_5h", "claude_7d", "codex_5h", "codex_7d")]
    peak = max((value for value in values if isinstance(value, (int, float))
                and not isinstance(value, bool) and 0 <= value <= 100), default=None)
    if peak is None:
        return None, None
    if peak >= 85:
        return "crit", "panic"
    if peak >= 60 or any(status.get(key) is True for key in
                         ("claude_5h_forecast_100", "claude_7d_forecast_100",
                          "codex_5h_forecast_100", "codex_7d_forecast_100")):
        return "warn", "worried"
    return "ok", "happy"


def forecast_100(old_value, old_at, old_reset, new_value, new_at, new_reset):
    """Only extrapolate a measured rise over at least five minutes in the same reset window."""
    if not all(isinstance(value, (int, float)) and not isinstance(value, bool)
               for value in (old_value, old_at, old_reset, new_value, new_at, new_reset)):
        return False
    elapsed = new_at - old_at
    if elapsed < 300 or abs(old_reset - new_reset) > 5 or new_reset <= new_at or new_value <= old_value:
        return False
    return new_value + (new_value - old_value) / elapsed * (new_reset - new_at) >= 100


def merge_status(status, reading, at):
    status = dict(status) if isinstance(status, dict) else {}
    old_at = parse_time(status.get("codex_data_at"))
    if old_at is not None and old_at > at:
        return None
    for prefix in ("codex_5h", "codex_7d"):
        status[prefix + "_forecast_100"] = forecast_100(
            status.get(prefix), old_at, status.get(prefix + "_resets_at"),
            reading.get(prefix), at, reading.get(prefix + "_resets_at"))
    status.update(reading)
    level, mood = level_for(status)
    if level:
        status["level"], status["mood"] = level, mood
    status["updated_at"] = iso(at)
    return status


def run(fetch=rpc_rate_limits, at=None):
    at = time.time() if at is None else at
    reading = parse_response(fetch(), at)
    if reading is None:
        raise RuntimeError("Codex app-server returned no usable rate limit window")
    directory = watcher_dir()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / ".status.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / "status.json"
        merged = merge_status(read_json(path), reading, at)
        if merged is not None:
            write_json(path, merged)
    return reading


if __name__ == "__main__":
    try:
        result = run()
        if "--print" in sys.argv[1:]:
            print(json.dumps(result, indent=2))
    except (OSError, RuntimeError) as error:
        print(f"LimitNotch Codex usage: {error}", file=sys.stderr)
        sys.exit(1)
