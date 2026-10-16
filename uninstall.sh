#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'LimitNotch: %s\n' "$1" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required."
[[ -n "${HOME:-}" && -d "$HOME" ]] || fail "HOME must point to your home directory."
[[ "$(id -u)" != 0 ]] || fail "Run this as your regular macOS user, without sudo."

for label in dev.kappaemme.limitnotch dev.kappaemme.limitnotch.claude-live; do
    service="gui/$(id -u)/$label"
    if launchctl print "$service" >/dev/null 2>&1; then
        launchctl bootout "$service" || fail "Could not stop the LaunchAgent $label."
    fi
    rm -f -- "$HOME/Library/LaunchAgents/$label.plist"
done
rm -rf -- "$HOME/.limit-notch"

printf 'LimitNotch removed. %s/.usage-watcher was left untouched.\n' "$HOME"
