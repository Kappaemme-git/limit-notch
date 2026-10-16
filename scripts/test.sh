#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
mkdir -p .build/clang-module-cache .build/swiftpm-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache"
swift test --disable-sandbox --build-system native \
    --cache-path "$PWD/.build/cache" \
    --config-path "$PWD/.build/config" \
    --security-path "$PWD/.build/security" \
    --manifest-cache local
