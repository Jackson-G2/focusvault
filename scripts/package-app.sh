#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="FocusVault"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$ROOT_DIR/dist"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

swift build -c release --product focusvault-app
swift build -c release --product focusvault

install -m 755 "$ROOT_DIR/.build/release/focusvault-app" "$CONTENTS_DIR/MacOS/$APP_NAME"
install -m 755 "$ROOT_DIR/.build/release/focusvault" "$CONTENTS_DIR/Resources/focusvault-cli"
cp "$ROOT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$ROOT_DIR/BrowserExtension" "$CONTENTS_DIR/Resources/BrowserExtension"

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/${APP_NAME}-macOS.zip"

printf 'Created app: %s\n' "$APP_DIR"
printf 'Created archive: %s\n' "$ROOT_DIR/dist/${APP_NAME}-macOS.zip"
/usr/bin/file "$APP_DIR/Contents/MacOS/$APP_NAME"
