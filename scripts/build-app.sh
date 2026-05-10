#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/build/MacNotificationBarkBridge.app"
EXECUTABLE_NAME="mac-notification-bark-bridge"
RESOURCE_BUNDLE_NAME="MacNotificationBarkBridge_MacNotificationBarkBridge.bundle"
APP_ICON_NAME="AppIcon.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
BUNDLE_IDENTIFIER="local.codex.MacNotificationBarkBridge"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

rm -f "$APP_DIR/Contents/Info.plist"
rm -f "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
rm -rf "$APP_DIR/Contents/Resources/$RESOURCE_BUNDLE_NAME"
rm -f "$APP_DIR/Contents/Resources/$APP_ICON_NAME"

ditto "$ROOT_DIR/Packaging/MacNotificationBarkBridge-Info.plist" "$APP_DIR/Contents/Info.plist"
ditto "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
ditto "$ROOT_DIR/Packaging/$APP_ICON_NAME" "$APP_DIR/Contents/Resources/$APP_ICON_NAME"

if [ -d "$BIN_DIR/$RESOURCE_BUNDLE_NAME" ]; then
  ditto "$BIN_DIR/$RESOURCE_BUNDLE_NAME" "$APP_DIR/Contents/Resources/$RESOURCE_BUNDLE_NAME"
fi

chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

if [ -n "$SIGNING_IDENTITY" ]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  codesign \
    --force \
    --deep \
    --sign - \
    --identifier "$BUNDLE_IDENTIFIER" \
    --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
    "$APP_DIR"
fi

echo "$APP_DIR"
