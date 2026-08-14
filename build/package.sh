#!/bin/bash
# GateTree distribution packager.
#
# Creates a self-contained .app and drag-to-Applications .dmg. With a valid
# Developer ID certificate it signs and notarizes the result; otherwise it
# produces an ad-hoc signed developer build.
#
# Usage:
#   ./build/package.sh [version]
#
# Optional environment:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="GateTree-notary"
#
# To store the notarization profile once on the release Mac:
#   xcrun notarytool store-credentials GateTree-notary \
#     --apple-id you@example.com --team-id TEAMID --password app-password

set -euo pipefail

VERSION="${1:-v0.2.0-alpha}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build-release"
DIST_DIR="$PROJECT_ROOT/.dist"
STAGE_DIR="$DIST_DIR/dmg-stage"
APP_NAME="GateTree"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-GateTree-notary}"

SIGN_MODE="adhoc"
if [ -n "$DEVELOPER_ID" ] && \
   security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID"; then
  SIGN_MODE="developer-id"
fi

cd "$PROJECT_ROOT"

echo "==> Cleaning previous package output"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building Release ($SIGN_MODE signing)"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

[ -d "$APP_PATH" ] || {
  echo "ERROR: expected app was not produced: $APP_PATH" >&2
  exit 1
}

cp -R "$APP_PATH" "$DIST_DIR/$APP_NAME.app"
APP_PATH="$DIST_DIR/$APP_NAME.app"

if [ "$SIGN_MODE" = "developer-id" ]; then
  echo "==> Signing app with Developer ID"
  codesign --force --deep --sign "$DEVELOPER_ID" \
    --options runtime --timestamp "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "==> Ad-hoc signing app (not suitable for public distribution)"
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "==> Creating drag-to-Applications disk image"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ "$SIGN_MODE" = "developer-id" ]; then
  echo "==> Signing disk image"
  codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing disk image"
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
  else
    echo "WARNING: notarization profile '$NOTARY_PROFILE' was not found; skipped."
  fi
fi

echo
echo "Package created: $DMG_PATH"
