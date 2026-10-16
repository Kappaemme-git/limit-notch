#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
mkdir -p .build/clang-module-cache .build/swiftpm-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache"
swift build --disable-sandbox --build-system native -c release \
    --cache-path "$PWD/.build/cache" \
    --config-path "$PWD/.build/config" \
    --security-path "$PWD/.build/security" \
    --manifest-cache local

app_dir="dist/LimitNotch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/LimitNotch "$app_dir/Contents/MacOS/LimitNotch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# SwiftPM signs the standalone executable. That signature does not cover an .app bundle.
codesign --remove-signature "$app_dir/Contents/MacOS/LimitNotch"
printf 'Created %s\n' "$app_dir"
