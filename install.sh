#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'LimitNotch: %s\n' "$1" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required."
[[ -n "${HOME:-}" && -d "$HOME" ]] || fail "HOME must point to your home directory."
[[ "$(id -u)" != 0 ]] || fail "Run this as your regular macOS user, without sudo."

for tool in git swift /usr/bin/python3; do
    command -v "$tool" >/dev/null 2>&1 ||
        fail "$tool is missing. Install the Xcode Command Line Tools, then retry."
done
git --version >/dev/null 2>&1 ||
    fail "Git is not working. Check your Xcode Command Line Tools installation."
xcode-select -p >/dev/null 2>&1 ||
    fail "Xcode Command Line Tools are not configured. Install them, then retry."
swift --version >/dev/null 2>&1 ||
    fail "Swift is not working. Check your Xcode Command Line Tools installation."

macos_major=$(sw_vers -productVersion)
macos_major=${macos_major%%.*}
[[ "$macos_major" -ge 13 ]] || fail "macOS 13 or later is required."

repo_url="https://github.com/Kappaemme-git/limit-notch.git"
install_dir="$HOME/.limit-notch"
source_dir="$install_dir/src"
installed_binary="$install_dir/LimitNotch"
agent_dir="$HOME/Library/LaunchAgents"
agent_plist="$agent_dir/dev.kappaemme.limitnotch.plist"
label="dev.kappaemme.limitnotch"
domain="gui/$(id -u)"
service="$domain/$label"
helper="$install_dir/claude_live.py"
helper_label="dev.kappaemme.limitnotch.claude-live"
helper_plist="$agent_dir/$helper_label.plist"
helper_service="$domain/$helper_label"
codex_helper="$install_dir/codex_live.py"
codex_label="dev.kappaemme.limitnotch.codex-live"
codex_plist="$agent_dir/$codex_label.plist"
codex_service="$domain/$codex_label"
codex_cli=$(command -v codex || true)
[[ -n "$codex_cli" ]] || fail "Codex CLI is missing. Install Codex before enabling live Codex usage."
node_cli=$(command -v node || true)
codex_path="$(dirname "$codex_cli"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if [[ -n "$node_cli" ]]; then
    codex_path="$(dirname "$node_cli"):$codex_path"
fi

mkdir -p "$install_dir"
if [[ -e "$source_dir" || -L "$source_dir" ]]; then
    [[ -d "$source_dir/.git" ]] || fail "$source_dir exists but is not a Git checkout."
    origin=$(git -C "$source_dir" config --get remote.origin.url) ||
        fail "Cannot read the existing checkout's origin."
    [[ "$origin" == "$repo_url" ]] ||
        fail "$source_dir points to a different Git repository."
    changes=$(git -C "$source_dir" status --porcelain) ||
        fail "Cannot inspect the existing checkout."
    [[ -z "$changes" ]] ||
        fail "$source_dir has local changes. Resolve them before updating."
    git -C "$source_dir" checkout main
    git -C "$source_dir" fetch origin main
    git -C "$source_dir" merge --ff-only FETCH_HEAD
    [[ "$(git -C "$source_dir" rev-parse HEAD)" == "$(git -C "$source_dir" rev-parse FETCH_HEAD)" ]] ||
        fail "The local main branch differs from the published main branch."
else
    git clone --branch main --single-branch "$repo_url" "$source_dir"
fi

(cd "$source_dir" && swift build -c release)
source_binary="$source_dir/.build/release/LimitNotch"
[[ -x "$source_binary" ]] || fail "The release build did not produce LimitNotch."

[[ -f "$source_dir/scripts/claude_live.py" ]] || fail "The checkout has no scripts/claude_live.py."
[[ -f "$source_dir/scripts/codex_live.py" ]] || fail "The checkout has no scripts/codex_live.py."

mkdir -p "$HOME/.usage-watcher" "$agent_dir"
temp_binary=$(mktemp "$install_dir/.LimitNotch.XXXXXX")
temp_helper=$(mktemp "$install_dir/.claude_live.XXXXXX")
temp_codex_helper=$(mktemp "$install_dir/.codex_live.XXXXXX")
temp_plist=$(mktemp "$agent_dir/.dev.kappaemme.limitnotch.XXXXXX")
temp_helper_plist=$(mktemp "$agent_dir/.dev.kappaemme.limitnotch.claude-live.XXXXXX")
temp_codex_plist=$(mktemp "$agent_dir/.dev.kappaemme.limitnotch.codex-live.XXXXXX")
cleanup() {
    rm -f -- "$temp_binary" "$temp_helper" "$temp_codex_helper" "$temp_plist" "$temp_helper_plist" "$temp_codex_plist"
}
trap cleanup EXIT

install -m 755 "$source_binary" "$temp_binary"
install -m 755 "$source_dir/scripts/claude_live.py" "$temp_helper"
install -m 755 "$source_dir/scripts/codex_live.py" "$temp_codex_helper"

xml() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

cat > "$temp_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(xml "$installed_binary")</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST
plutil -lint "$temp_plist" >/dev/null || fail "Could not create a valid LaunchAgent plist."

# Refreshes Claude plan usage every 60 seconds from the endpoint behind Claude Code's /usage.
cat > "$temp_helper_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$helper_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>-I</string>
        <string>$(xml "$helper")</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$(xml "$install_dir/claude_live.log")</string>
</dict>
</plist>
PLIST
plutil -lint "$temp_helper_plist" >/dev/null || fail "Could not create a valid helper LaunchAgent plist."

cat > "$temp_codex_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$codex_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>-I</string>
        <string>$(xml "$codex_helper")</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CODEX_CLI</key><string>$(xml "$codex_cli")</string>
        <key>PATH</key><string>$(xml "$codex_path")</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardErrorPath</key>
    <string>$(xml "$install_dir/codex_live.log")</string>
</dict>
</plist>
PLIST
plutil -lint "$temp_codex_plist" >/dev/null || fail "Could not create a valid Codex helper LaunchAgent plist."

for running in "$service" "$helper_service" "$codex_service"; do
    if launchctl print "$running" >/dev/null 2>&1; then
        launchctl bootout "$running" || fail "Could not stop the existing LaunchAgent $running."
    fi
done
mv -f "$temp_binary" "$installed_binary"
mv -f "$temp_helper" "$helper"
mv -f "$temp_codex_helper" "$codex_helper"
mv -f "$temp_plist" "$agent_plist"
mv -f "$temp_helper_plist" "$helper_plist"
mv -f "$temp_codex_plist" "$codex_plist"
launchctl bootstrap "$domain" "$helper_plist" ||
    fail "Could not start the Claude usage helper. Check your macOS GUI session."
launchctl bootstrap "$domain" "$codex_plist" ||
    fail "Could not start the Codex usage helper. Check your macOS GUI session."
launchctl bootstrap "$domain" "$agent_plist" ||
    fail "Could not start the LaunchAgent. Check your macOS GUI session."

printf 'LimitNotch installed and started. It reads %s/.usage-watcher/status.json.\n' "$HOME"
printf 'Claude usage refreshes every 60 s while you are signed in to Claude Code.\n'
printf 'Codex usage refreshes every 60 s through the installed Codex CLI.\n'
