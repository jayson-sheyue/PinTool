#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="PinTool.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/PinTool" "$APP/Contents/MacOS/PinTool"
cp "Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/PinTool"
codesign --force --sign - "$APP"
echo "Built $APP"
