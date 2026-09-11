#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LUMA_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_DIR="$PROJECT_DIR/../Luma.app"
swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Luma" "$APP_DIR/Contents/MacOS/Luma"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
