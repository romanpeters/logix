#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LogixMouseMapper"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

swift build -c release

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
: > "$RESOURCES_DIR/.keep"

cp -f "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.logix.mousemapper</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Always sign the final bundle so LaunchServices doesn't reject stale/invalid signatures.
# If SIGNING_IDENTITY is unset, use ad-hoc signing ("-").
if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "Built $APP_DIR"
