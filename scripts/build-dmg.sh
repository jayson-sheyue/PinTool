#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
ARCH="$(uname -m)"

swift build -c release

STAGE="$(mktemp -d)"
DMG_ROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$STAGE" "$DMG_ROOT"
}
trap cleanup EXIT

APP="$STAGE/PinTool.app"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/PinTool" "$APP/Contents/MacOS/PinTool"
cp "Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/PinTool"
# Ad-hoc only. This machine has no Developer ID identity, so the result
# cannot be notarized and Gatekeeper will block it on another Mac.
codesign --force --sign - "$APP"

cp -R "$APP" "$DMG_ROOT/PinTool.app"
ln -s /Applications "$DMG_ROOT/Applications"

mkdir -p dist
OUT="dist/PinTool-${VERSION}-${ARCH}.dmg"
rm -f "$OUT"
hdiutil create -volname "钉图" -srcfolder "$DMG_ROOT" -ov -format UDZO "$OUT"
echo "Built $OUT"
