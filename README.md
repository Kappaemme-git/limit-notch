# LimitNotch

LimitNotch is a small macOS notch companion built with SwiftUI. It reads `~/.usage-watcher/status.json` every 30 seconds and when opened. It does not use the network, API keys, or external dependencies at runtime.

The original vector creature bounces in green when `mood` is `happy` or `level` is `ok`, trembles in yellow for `worried` or `warn`, panics in red for `panic` or `crit`, and sleeps in gray when the file is missing, invalid, or over one hour old. `mood` takes priority over `level`. Hover or click to see usage, reset times, source timestamps, and the note. Missing or null values display as `—`.

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

The script clones or updates the `main` branch in `~/.limit-notch/src`, runs `swift build -c release`, installs `~/.limit-notch/LimitNotch`, and starts `~/Library/LaunchAgents/dev.kappaemme.limitnotch.plist`. Running the same command again updates the installation. It creates `~/.usage-watcher` if needed, but does not create or modify `status.json`. The creature stays gray until another program writes a current status file.

The app runs without a Dock icon. Right-click the creature and choose **Quit LimitNotch** to stop it for the current session. The LaunchAgent starts it again at login and restarts it after a crash.

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
