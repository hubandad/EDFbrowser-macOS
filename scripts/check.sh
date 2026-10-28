#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/module-cache"
swift run --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security EDFCoreCheck "$@"
