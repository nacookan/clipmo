#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/Clipmo.app"
MODULE_CACHE_DIR="$ROOT_DIR/.swiftpm-cache/ModuleCache"
HOME_DIR="$ROOT_DIR/.home"
EXECUTABLE_PATH=""

mkdir -p "$MODULE_CACHE_DIR" "$HOME_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

HOME="$HOME_DIR" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
swift build -c release --package-path "$ROOT_DIR"

for candidate in \
  "$ROOT_DIR/.build/release/Clipmo" \
  "$ROOT_DIR/.build/arm64-apple-macosx/release/Clipmo" \
  "$ROOT_DIR/.build/x86_64-apple-macosx/release/Clipmo"
do
  if [[ -f "$candidate" ]]; then
    EXECUTABLE_PATH="$candidate"
    break
  fi
done

if [[ -z "$EXECUTABLE_PATH" ]]; then
  echo "Clipmo executable not found after build." >&2
  exit 1
fi

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/Clipmo"
chmod +x "$APP_DIR/Contents/MacOS/Clipmo"

for localization_dir in "$ROOT_DIR"/Resources/*.lproj(N)
do
  cp -R "$localization_dir" "$APP_DIR/Contents/Resources/"
done

if [[ -d "$ROOT_DIR/Resources/Assets.xcassets" ]]; then
  xcrun actool \
    --compile "$APP_DIR/Contents/Resources" \
    --app-icon AppIcon \
    --output-partial-info-plist "$APP_DIR/Contents/Resources/actool-info.plist" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    "$ROOT_DIR/Resources/Assets.xcassets" >/dev/null

  rm -f "$APP_DIR/Contents/Resources/actool-info.plist"
fi

ENTITLEMENTS_PATH="$ROOT_DIR/Resources/Clipmo.entitlements"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"

echo "$APP_DIR"
