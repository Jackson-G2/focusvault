#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Vaulty"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$ROOT_DIR/dist"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

swift build -c release --product vaulty-app
swift build -c release --product vaulty

install -m 755 "$ROOT_DIR/.build/release/vaulty-app" "$CONTENTS_DIR/MacOS/$APP_NAME"
install -m 755 "$ROOT_DIR/.build/release/vaulty" "$CONTENTS_DIR/Resources/vaulty-cli"
# Keep the old helper filename available to older local integrations.
install -m 755 "$ROOT_DIR/.build/release/vaulty" "$CONTENTS_DIR/Resources/focusvault-cli"
cp "$ROOT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/AppResources/Vaulty.icns" "$CONTENTS_DIR/Resources/Vaulty.icns"
cp -R "$ROOT_DIR/BrowserExtension" "$CONTENTS_DIR/Resources/BrowserExtension"
cp -R "$ROOT_DIR/Brand" "$CONTENTS_DIR/Resources/Brand"
mkdir -p "$CONTENTS_DIR/Resources/ResearchAgent"
cp "$ROOT_DIR/ResearchAgent/recommend.py" "$CONTENTS_DIR/Resources/ResearchAgent/recommend.py"

"$CONTENTS_DIR/Resources/vaulty-cli" internal-verify-guard-config
/bin/test -f "$CONTENTS_DIR/Resources/BrowserExtension/session-policy.js"
/bin/test -f "$CONTENTS_DIR/Resources/BrowserExtension/tests/session-policy.test.js"
/bin/test -f "$CONTENTS_DIR/Resources/Vaulty.icns"

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/${APP_NAME}-macOS.zip"

printf 'Created app: %s\n' "$APP_DIR"
printf 'Created archive: %s\n' "$ROOT_DIR/dist/${APP_NAME}-macOS.zip"
/usr/bin/file "$APP_DIR/Contents/MacOS/$APP_NAME"
