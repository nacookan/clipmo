#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
ICONSET_DIR="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
BASE_PNG="$ICONSET_DIR/icon_512x512@2x.png"
MODULE_CACHE_DIR="$ROOT_DIR/.swiftpm-cache/ModuleCache"
HOME_DIR="$ROOT_DIR/.home"

mkdir -p "$MODULE_CACHE_DIR" "$HOME_DIR"
mkdir -p "$ICONSET_DIR"
find "$ICONSET_DIR" -maxdepth 1 -type f -name '*.png' -delete

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

HOME="$HOME_DIR" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
swift "$ROOT_DIR/scripts/render-app-icon.swift" "$BASE_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
done

sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null

echo "$ICONSET_DIR"
