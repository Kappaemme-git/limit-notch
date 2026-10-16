# LimitNotch

LimitNotch lives in the MacBook notch. It reads `~/.usage-watcher/status.json` (and `claude_live.json`) every 10 seconds and whenever it opens. The app itself does not use the network, API keys, or external dependencies.

Collapsed, the black shape matches the camera housing with no ears: its width, height and position come from `NSScreen.auxiliaryTopLeftArea`, `auxiliaryTopRightArea` and `safeAreaInsets.top`. macOS does not expose the corner radius; an 8 pt visual match is used independently of height. Hover springs it open into a panel with Claude 5h, Claude weekly and Codex weekly bars (and Codex 5h when supplied), reset countdowns, and data age. The fixed-size drawing surface avoids layout work during the shape morph; the mascot uses an AppKit display link at the screen refresh rate, up to 120 fps. On displays without a notch it becomes a small pill at the top center of the screen. The panel appears on every Space, stays above full-screen apps, and has no Dock or menu bar icon.

The mascot is a flat electric blue circle with two small white vertical oval eyes slightly left of center and no mouth. It breathes, blinks at random intervals and glances around, leaning toward where it looks. Its mood follows the highest reported window, including a forecast that reaches 100% before reset:

| Status | Mascot |
| --- | --- |
| `happy` / `ok` | Relaxed blinking and the occasional squash-and-stretch hop |
| `worried` / `warn` | Smaller, raised eyes, a slow wobble and more frequent glances |
| `panic` / `crit` | Fast blinking, a quick shake and a red glow |
| missing, invalid, or older than one hour | Asleep: closed eyes, slow breathing, a floating Zzz |

[`docs/mascot.svg`](docs/mascot.svg) is an SVG + CSS version of the same character for web pages; set `data-mood` to `happy`, `worried`, `panic` or `sleep`.

## Requirements

- macOS 13 or later.
- Xcode Command Line Tools, providing `swift` and `git`.
- Codex CLI installed and signed in for live Codex usage.
- A connection to GitHub during installation and updates.

LimitNotch is compiled locally from source. It is not signed with a Developer ID certificate or notarized. On Apple silicon, the toolchain may add the ad hoc signature macOS requires for locally built executables; it does not identify a developer. No Developer ID certificate or API key is needed.

## Install or update

Run this as your regular macOS user, without `sudo`:

```sh
curl -fsSL https://raw.githubusercontent.com/Kappaemme-git/limit-notch/main/install.sh | bash
```

The script clones or updates the `main` branch in `~/.limit-notch/src`, runs `swift build -c release`, installs the app and its helpers, and starts three LaunchAgents: `dev.kappaemme.limitnotch` (the app), `dev.kappaemme.limitnotch.claude-live` and `dev.kappaemme.limitnotch.codex-live` (usage helpers, every 60 seconds). The installer requires the Codex CLI for live Codex usage. Running the same command again updates the installation. It creates `~/.usage-watcher` if needed.

## Live Claude usage

`claude_live.py` reads Claude plan usage from `https://api.anthropic.com/api/oauth/usage`, the endpoint behind Claude Code's `/usage` command, using the OAuth login Claude Code already stores (the `Claude Code-credentials` Keychain item, or `~/.claude/.credentials.json`). The token is only sent to `api.anthropic.com`; the helper never prints, copies or refreshes it. It needs Claude Code installed and signed in to a Claude subscription; when the token has expired (Claude Code unused for several hours), run `claude` once to refresh it.

## Live Codex usage

`codex_live.py` asks the installed `codex app-server` for `account/rateLimits/read` every 60 seconds. It selects the `codex` account bucket and its 7-day window by `windowDurationMins = 10080`; it also captures a 5-hour window when present. The response provides `usedPercent` and `resetsAt` directly. The helper never opens Codex credential files or prints account data beyond the usage fields. It updates only `codex_*` fields in `status.json` plus the shared `level`, `mood` and `updated_at` summary, preserving all `claude_*` values. Both helpers lock the status file while merging so simultaneous refreshes do not lose data.

Every run writes the freshest reading to `~/.usage-watcher/claude_live.json` and merges `claude_5h`, `claude_7d`, `claude_5h_resets_at`, `claude_7d_resets_at`, `claude_data_at` and `claude_source` into `status.json` (creating it if needed, keeping every other field, and recomputing `level`/`mood`). When the endpoint fails it backs off (honoring `Retry-After`) and falls back to the newest of: the last good reading, a Claude Code status line snapshot in `~/.usage-watcher/claude.json` (`rate_limits`), and the Claude desktop app's `plan-usage-history.json`, which is only written occasionally and has no reset times. `claude_source` is `claude-code-oauth-usage`, `claude-code-statusline` or `claude-desktop-app`. Errors go to `~/.limit-notch/claude_live.log`; run `python3 ~/.limit-notch/claude_live.py --print` to see the current reading.

The app runs without a Dock icon. Right-click the notch panel and choose **Quit LimitNotch** to stop it for the current session. The LaunchAgent starts it again at login and restarts it after a crash.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/Kappaemme-git/limit-notch/main/uninstall.sh | bash
```

This stops and removes all three LaunchAgents and deletes `~/.limit-notch`. It leaves `~/.usage-watcher` and its data untouched.

## Status file

Write `~/.usage-watcher/status.json` with this schema:

```json
{
  "claude_5h": 49.9,
  "claude_7d": 81.2,
  "codex_5h": null,
  "codex_7d": 2.0,
  "claude_5h_resets_at": null,
  "claude_7d_resets_at": null,
  "codex_5h_resets_at": null,
  "codex_7d_resets_at": 1792655962,
  "claude_data_at": 1792159950,
  "claude_source": "claude-code-oauth-usage",
  "codex_data_at": 1792159940,
  "codex_source": "codex-app-server",
  "claude_app": { "fh": 41.5, "sd": 62.3, "at": 1792159930 },
  "level": "warn",
  "mood": "worried",
  "note": "Claude 5h 49.9%, weekly 81.2%; Codex weekly 2%.",
  "updated_at": "2026-10-16T15:32:00Z"
}
```

`claude_5h`, `claude_7d`, `codex_5h`, `codex_7d`, and `claude_app.fh`/`sd` are percentages from 0 to 100. Reset timestamps are Unix seconds and may be `null`. `claude_data_at`, `codex_data_at`, and `claude_app.at` accept Unix seconds or ISO 8601 timestamps. `level` is `ok`, `warn`, or `crit`; `mood` is `happy`, `worried`, or `panic`. The highest reported window decides the mood: under 60% is happy, 60–84.9% is worried, and 85% or more is panic. A measured usage trend that projects 100% before the same window resets also sets worried. `note` is optional text. `updated_at` is an ISO 8601 UTC timestamp and controls the one-hour freshness limit. Replace the example timestamps with current values. Dates appear in the Mac's local time zone with English labels. The former generic `reset` field is ignored.

## Develop locally

```sh
sh scripts/test.sh   # Swift tests plus both Python helper tests
swift build -c release
```

The release executable is `.build/release/LimitNotch`. `sh scripts/build-app.sh` also creates an unsigned `dist/LimitNotch.app` for local experiments. The executable is the verified launch path; opening the app bundle through Launch Services has not been verified.
