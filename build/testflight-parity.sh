#!/usr/bin/env bash
# Builds the app locally with the same Release configuration and verifies the
# sandbox-critical metadata used by the TestFlight archive. It never uploads.
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
grep -q '<key>com.apple.security.app-sandbox</key><true/>' <<< "$entitlements"
grep -q '<key>com.apple.security.network.client</key><true/>' <<< "$entitlements"
grep -q '<key>com.apple.security.files.user-selected.read-only</key><true/>' <<< "$entitlements"

echo "TestFlight parity checks passed: $app_path"
