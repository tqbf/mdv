#!/usr/bin/env bash
# Build mdv with SwiftPM (no Xcode IDE needed) and assemble a .app bundle.
#
# Usage: ./build.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]"; exit 1 ;;
esac

cd "$(dirname "$0")"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/mdv"
[ -x "$BIN" ] || { echo "✗ binary missing at $BIN"; exit 1; }

APP="build/mdv.app"
echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN"                       "$APP/Contents/MacOS/mdv"
cp mdv/Info.plist               "$APP/Contents/Info.plist"
cp mdv/AppIcon.icns             "$APP/Contents/Resources/AppIcon.icns"
cp mdv/Fonts/*.otf              "$APP/Contents/Resources/"
cp mdv/Grammars/*-highlights.scm "$APP/Contents/Resources/"

# Bundle the CLI helper so the app can install /usr/local/bin/mdv pointing
# at this script — the in-app "Install Command Line Tool…" menu symlinks
# to this path.
cp bin/mdv                       "$APP/Contents/Resources/mdv"
chmod +x                         "$APP/Contents/Resources/mdv"

# Bundle the in-app help doc; HelpManager copies it out to a stable path
# under ~/Library/Application Support/mdv on demand so bookmarks survive.
cp mdv/Help.md                   "$APP/Contents/Resources/Help.md"

echo "→ codesigning (adhoc)"
codesign --force --sign - --entitlements mdv/mdv.entitlements "$APP"

echo "✓ $APP"
