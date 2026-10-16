# LimitNotch

LimitNotch lives in the MacBook notch. It is a small macOS companion built with SwiftUI that reads `~/.usage-watcher/status.json` every 30 seconds and whenever it opens. It does not use the network, API keys, or external dependencies at runtime.

Collapsed, a black extension hugs the camera housing: a little blue mascot sits on the left and a ring on the right shows the highest of the three usage values. Hover (or click to pin) and it springs open into a Dynamic Island-style panel with Claude 5h, Claude 7d and Codex 7d bars, time until each reset (`—` when unknown) and when the data was last updated. On displays without a notch it becomes a small pill at the top center of the screen. The panel appears on every Space, stays above full-screen apps, and has no Dock or menu bar icon.

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

The script clones or updates the `main` branch in `~/.limit-notch/src`, runs `swift build -c release`, installs `~/.limit-notch/LimitNotch`, and starts `~/Library/LaunchAgents/dev.kappaemme.limitnotch.plist`. Running the same command again updates the installation. It creates `~/.usage-watcher` if needed, but does not create or modify `status.json`. The mascot sleeps until another program writes a current status file.

The app runs without a Dock icon. Right-click the notch panel and choose **Quit LimitNotch** to stop it for the current session. The LaunchAgent starts it again at login and restarts it after a crash.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/Kappaemme-git/limit-notch/main/uninstall.sh | bash
```

This stops and removes the LaunchAgent and deletes `~/.limit-notch`. It leaves `~/.usage-watcher` and its data untouched.

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
  "codex_data_at": 1792159940,
  "claude_app": { "fh": 41.5, "sd": 62.3, "at": 1792159930 },
  "level": "ok",
  "mood": "happy",
  "note": "All systems normal",
  "updated_at": "2026-10-16T15:32:00Z"
}
```

`claude_5h`, `claude_7d`, `codex_7d`, and `claude_app.fh`/`sd` are percentages from 0 to 100. Reset timestamps are Unix seconds and may be `null`, as the Claude desktop app does not provide them. `claude_data_at`, `codex_data_at`, and `claude_app.at` accept Unix seconds or ISO 8601 timestamps. `level` is `ok`, `warn`, or `crit`; `mood` is `happy`, `worried`, or `panic`. `note` is optional text. `updated_at` is an ISO 8601 UTC timestamp and controls the one-hour freshness limit. Replace the example timestamps with current values. Dates appear in the Mac's local time zone with English labels. The former generic `reset` field is ignored.

## Develop locally

```sh
sh scripts/test.sh
swift build -c release
```

The release executable is `.build/release/LimitNotch`. `sh scripts/build-app.sh` also creates an unsigned `dist/LimitNotch.app` for local experiments. The executable is the verified launch path; opening the app bundle through Launch Services has not been verified.
