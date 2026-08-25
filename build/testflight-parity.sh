#!/usr/bin/env bash
# Builds the app locally with the same Release configuration as the notarized
# Developer ID DMG. It never uploads.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

./build/generate-project.sh
xcodebuild \
  -project GateTree.xcodeproj \
  -scheme GateTree \
  -configuration Release \
  -sdk macosx \
  ARCHS="$(uname -m)" \
  ONLY_ACTIVE_ARCH=YES \
  build

app_path="$(xcodebuild -project GateTree.xcodeproj -scheme GateTree -configuration Release -showBuildSettings \
  | awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { target=$2 } /^[[:space:]]*WRAPPER_NAME = / { wrapper=$2 } END { print target "/" wrapper }')"
info_plist="$app_path/Contents/Info.plist"
entitlements="$(codesign -d --entitlements :- "$app_path" 2>&1)"

plutil -extract CFBundleIdentifier raw "$info_plist" | grep -qx 'com.gatetree.app'
plutil -extract CFBundleShortVersionString raw "$info_plist" | grep -qx "$(tr -d '[:space:]' < VERSION)"
plutil -extract ITSAppUsesNonExemptEncryption raw "$info_plist" | grep -qx 'false'
grep -q '<key>com.apple.security.network.client</key><true/>' <<< "$entitlements"

if grep -q '<key>com.apple.security.app-sandbox</key><true/>' <<< "$entitlements"; then
  echo "ERROR: GateTree must not be sandboxed in Developer ID mode." >&2
  exit 1
fi

echo "Developer ID parity checks passed: $app_path"
