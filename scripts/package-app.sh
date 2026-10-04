#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Vaulty"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"

# A failed build must not delete the previous working artifact or unrelated dist files.
swift build -c release --product vaulty-app
swift build -c release --product vaulty
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.vaulty-package.XXXXXX")"
cleanup() {
  # Roll back if replacing the app failed after moving its predecessor aside.
  if [[ -e "$STAGING_DIR/previous.app" && ! -e "$APP_DIR" ]]; then
    mv "$STAGING_DIR/previous.app" "$APP_DIR"
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
CONTENTS_DIR="$STAGED_APP/Contents"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources/ResearchAgent"

install -m 755 "$ROOT_DIR/.build/release/vaulty-app" "$CONTENTS_DIR/MacOS/$APP_NAME"
install -m 755 "$ROOT_DIR/.build/release/vaulty" "$CONTENTS_DIR/Resources/vaulty-cli"
# Keep the old helper filename available to older local integrations.
install -m 755 "$ROOT_DIR/.build/release/vaulty" "$CONTENTS_DIR/Resources/focusvault-cli"
cp "$ROOT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/AppResources/Vaulty.icns" "$CONTENTS_DIR/Resources/Vaulty.icns"
cp -R "$ROOT_DIR/BrowserExtension" "$CONTENTS_DIR/Resources/BrowserExtension"
cp -R "$ROOT_DIR/Brand" "$CONTENTS_DIR/Resources/Brand"
# The entrypoint now imports focused sibling modules; bundle all runtime modules,
# not tests or interpreter caches, and import them from outside the source checkout.
for module in "$ROOT_DIR/ResearchAgent/"*.py; do
  install -m 644 "$module" "$CONTENTS_DIR/Resources/ResearchAgent/"
done

"$CONTENTS_DIR/Resources/vaulty-cli" internal-verify-guard-config
/bin/test -f "$CONTENTS_DIR/Resources/BrowserExtension/session-policy.js"
/bin/test -f "$CONTENTS_DIR/Resources/Vaulty.icns"
PYTHONDONTWRITEBYTECODE=1 python3 "$CONTENTS_DIR/Resources/ResearchAgent/recommend.py" --help >/dev/null
/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/codesign --force --deep --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGING_DIR/${APP_NAME}-macOS.zip"
# Only validated outputs replace their exact predecessors.
if [[ -e "$APP_DIR" ]]; then mv "$APP_DIR" "$STAGING_DIR/previous.app"; fi
mv "$STAGED_APP" "$APP_DIR"
mv -f "$STAGING_DIR/${APP_NAME}-macOS.zip" "$DIST_DIR/${APP_NAME}-macOS.zip"

printf 'Created app: %s\n' "$APP_DIR"
printf 'Created archive: %s\n' "$DIST_DIR/${APP_NAME}-macOS.zip"
/usr/bin/file "$APP_DIR/Contents/MacOS/$APP_NAME"
