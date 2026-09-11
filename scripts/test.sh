#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LUMA_BUILD_DIR:-$PROJECT_DIR/.build}"
mkdir -p "$BUILD_DIR/verification"
swiftc -parse-as-library -swift-version 5 \
  "$PROJECT_DIR/Sources/Luma/Photo.swift" \
  "$PROJECT_DIR/Sources/Luma/Library.swift" \
  "$PROJECT_DIR/Sources/Luma/Folders.swift" \
  "$PROJECT_DIR/Tests/LumaChecks.swift" \
  -o "$BUILD_DIR/verification/LumaChecks"
"$BUILD_DIR/verification/LumaChecks"
