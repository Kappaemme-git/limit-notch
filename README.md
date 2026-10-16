# LimitNotch

LimitNotch lives in the MacBook notch. It is a small macOS companion built with SwiftUI that reads `~/.usage-watcher/status.json` (and `claude_live.json`, see below) every 10 seconds and whenever it opens. The app itself does not use the network, API keys, or external dependencies.

Collapsed, the black shape is exactly the camera housing: its width, height and position come from `NSScreen.auxiliaryTopLeftArea`, `auxiliaryTopRightArea` and `safeAreaInsets.top`, and its bottom corners use the hardware notch radius (a quarter of the notch height, which macOS does not report). Two thin ears beside it hold a tiny blue mascot on the left and a ring on the right showing the highest of the three usage values. Hover and it springs open into a Dynamic Island-style panel, its outline morphing continuously from the notch shape, with Claude 5h, Claude weekly and Codex weekly bars in green, yellow or red, live reset countdowns (`—` when unknown) and when the data was last updated. On displays without a notch it becomes a small pill at the top center of the screen. The panel appears on every Space, stays above full-screen apps, and has no Dock or menu bar icon.

The mascot is a round blue character with two white eyes. It breathes, blinks at random intervals and glances around, leaning toward where it looks. Its mood follows `mood` (or `level` when `mood` is missing):

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
- A connection to GitHub during installation and updates.

LimitNotch is compiled locally from source. It is not signed with a Developer ID certificate or notarized. On Apple silicon, the toolchain may add the ad hoc signature macOS requires for locally built executables; it does not identify a developer. No Developer ID certificate or API key is needed.

## Install or update

Run this as your regular macOS user, without `sudo`:

```sh
curl -fsSL https://raw.githubusercontent.com/Kappaemme-git/limit-notch/main/install.sh | bash
```

The script clones or updates the `main` branch in `~/.limit-notch/src`, runs `swift build -c release`, installs `~/.limit-notch/LimitNotch` and `~/.limit-notch/claude_live.py`, and starts two LaunchAgents: `dev.kappaemme.limitnotch` (the app) and `dev.kappaemme.limitnotch.claude-live` (the Claude usage helper, every 60 seconds). Running the same command again updates the installation. It creates `~/.usage-watcher` if needed.

## Live Claude usage

`claude_live.py` reads Claude plan usage from `https://api.anthropic.com/api/oauth/usage`, the endpoint behind Claude Code's `/usage` command, using the OAuth login Claude Code already stores (the `Claude Code-credentials` Keychain item, or `~/.claude/.credentials.json`). The token is only sent to `api.anthropic.com`; the helper never prints, copies or refreshes it. It needs Claude Code installed and signed in to a Claude subscription; when the token has expired (Claude Code unused for several hours), run `claude` once to refresh it.

Every run writes the freshest reading to `~/.usage-watcher/claude_live.json` and merges `claude_5h`, `claude_7d`, `claude_5h_resets_at`, `claude_7d_resets_at`, `claude_data_at` and `claude_source` into `status.json` (creating it if needed, keeping every other field, and recomputing `level`/`mood`). When the endpoint fails it backs off (honoring `Retry-After`) and falls back to the newest of: the last good reading, a Claude Code status line snapshot in `~/.usage-watcher/claude.json` (`rate_limits`), and the Claude desktop app's `plan-usage-history.json`, which is only written occasionally and has no reset times. `claude_source` is `claude-code-oauth-usage`, `claude-code-statusline` or `claude-desktop-app`. Errors go to `~/.limit-notch/claude_live.log`; run `python3 ~/.limit-notch/claude_live.py --print` to see the current reading.

The app runs without a Dock icon. Right-click the notch panel and choose **Quit LimitNotch** to stop it for the current session. The LaunchAgent starts it again at login and restarts it after a crash.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/Kappaemme-git/limit-notch/main/uninstall.sh | bash
```

This stops and removes both LaunchAgents and deletes `~/.limit-notch`. It leaves `~/.usage-watcher` and its data untouched.

## Status file

Write `~/.usage-watcher/status.json` with this schema:

```json
{
  "claude_5h": 49.9,
  "claude_7d": 81.2,
  "codex_7d": 2.0,
  "claude_5h_resets_at": null,
  "claude_7d_resets_at": null,
  "codex_7d_resets_at": 1792655962,
  "claude_data_at": 1792159950,
  "claude_source": "claude-code-oauth-usage",
  "codex_data_at": 1792159940,
  "claude_app": { "fh": 41.5, "sd": 62.3, "at": 1792159930 },
  "level": "ok",
  "mood": "happy",
  "note": "All systems normal",
  "updated_at": "2026-10-16T15:32:00Z"
}
```

`claude_5h`, `claude_7d`, `codex_7d`, and `claude_app.fh`/`sd` are percentages from 0 to 100. Reset timestamps are Unix seconds and may be `null`, as the Claude desktop app does not provide them. `claude_source` names where the Claude values came from. `claude_data_at`, `codex_data_at`, and `claude_app.at` accept Unix seconds or ISO 8601 timestamps. `level` is `ok`, `warn`, or `crit`; `mood` is `happy`, `worried`, or `panic`. When `claude_live.json` holds newer Claude data than `status.json`, the app uses it and derives the mood from the highest value (below 70% happy, below 90% worried, otherwise panic), the same thresholds that color the bars. `note` is optional text. `updated_at` is an ISO 8601 UTC timestamp and controls the one-hour freshness limit. Replace the example timestamps with current values. Dates appear in the Mac's local time zone with English labels. The former generic `reset` field is ignored.

## Develop locally

```sh
sh scripts/test.sh   # Swift tests plus the claude_live.py tests
swift build -c release
```

The release executable is `.build/release/LimitNotch`. `sh scripts/build-app.sh` also creates an unsigned `dist/LimitNotch.app` for local experiments. The executable is the verified launch path; opening the app bundle through Launch Services has not been verified.
