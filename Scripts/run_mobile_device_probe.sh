#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/wmm-mobile-device-probe"
BINARY_PATH="$BUILD_DIR/mobile_device_probe"

mkdir -p "$BUILD_DIR"

xcrun clang \
  -fobjc-arc \
  -framework Foundation \
  -I"$ROOT_DIR/World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice" \
  "$ROOT_DIR/Tools/mobile_device_probe.m" \
  "$ROOT_DIR/World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceBridge.m" \
  -o "$BINARY_PATH"

exec "$BINARY_PATH" "$@"
