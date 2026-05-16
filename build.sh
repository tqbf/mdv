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
# Download mermaid.min.js on demand so it stays out of git but CI can build.
# We pin the version *and* the SHA256 of the published artifact so the
# bundled JS is the exact bytes we reviewed — anything else (jsDelivr
# regression, stale local copy, deliberate tampering) hard-fails the build.
MERMAID_VERSION="11.4.1"
MERMAID_SHA256="a43bc1afd446f9c4cc66ac5dd45d02e8d65e26fc5344ec0ef787f88d6ddb6f9e"
MERMAID_JS="mdv/mermaid.min.js"

verify_mermaid() {
    local actual
    actual="$(shasum -a 256 "$MERMAID_JS" | awk '{print $1}')"
    if [ "$actual" != "$MERMAID_SHA256" ]; then
        echo "✗ mermaid.min.js sha256 mismatch"
        echo "  expected: $MERMAID_SHA256"
        echo "  actual:   $actual"
        echo "  delete $MERMAID_JS and re-run, or update MERMAID_SHA256 if"
        echo "  you intentionally bumped MERMAID_VERSION."
        exit 1
    fi
}

if [ ! -f "$MERMAID_JS" ]; then
    echo "→ downloading mermaid.js $MERMAID_VERSION"
    curl -fsSL "https://cdn.jsdelivr.net/npm/mermaid@${MERMAID_VERSION}/dist/mermaid.min.js" \
         -o "$MERMAID_JS.tmp"
    mv "$MERMAID_JS.tmp" "$MERMAID_JS"
fi
verify_mermaid
cp "$MERMAID_JS"                 "$APP/Contents/Resources/"

echo "→ codesigning (adhoc)"
codesign --force --sign - --entitlements mdv/mdv.entitlements "$APP"

echo "✓ $APP"
