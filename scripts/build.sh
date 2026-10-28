#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/module-cache"
configuration="${1:-release}"
output_dir="${EDF_OUTPUT_DIR:-$task_root/dist}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
swift build --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c "$configuration" --triple arm64-apple-macosx14.0 --product EDFBrowserMac
binary_dir="$(swift build --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c "$configuration" --triple arm64-apple-macosx14.0 --show-bin-path)"
stage_dir="$(mktemp -d /private/tmp/edfmac-package.XXXXXX)"
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/EDFBrowser Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/EDFBrowserMac" "$app/Contents/MacOS/EDFBrowserMac"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
if [ -f THIRD_PARTY_NOTICES.md ]; then cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"; fi
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
if [ -d Resources/Licenses ]; then cp -R Resources/Licenses "$app/Contents/Resources/"; fi
if [ -d "$binary_dir/EDFBrowserMac_EDFBrowserMac.bundle" ]; then cp -R "$binary_dir/EDFBrowserMac_EDFBrowserMac.bundle" "$app/Contents/Resources/"; fi
# iCloud/File Provider may attach Finder metadata to freshly created bundles.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$output_dir"
ditto --norsrc "$app" "$output_dir/EDFBrowser Mac.app"
ditto -c -k --norsrc --keepParent "$app" "$output_dir/EDFBrowserMac-$app_version-arm64.zip"
printf '\nBuilt: %s\n' "$output_dir/EDFBrowser Mac.app"
printf 'Signed archive: %s\n' "$output_dir/EDFBrowserMac-$app_version-arm64.zip"
