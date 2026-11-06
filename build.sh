#!/bin/bash
# 编译 StealthTicker.app（纯本地 Swift，无第三方依赖，不需要 Xcode 工程）
# 产物是 arm64 + x86_64 的通用二进制，Intel / Apple Silicon 都能跑。
set -euo pipefail
cd "$(dirname "$0")"

APP="StealthTicker.app"
CACHE=".build-cache"
DEPLOYMENT_TARGET="13.0"
[[ "$APP" == "StealthTicker.app" ]] || { echo "unexpected bundle path"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

compile_slice() {
  local arch="$1"
  swiftc \
    -O \
    -swift-version 5 \
    -module-cache-path "$CACHE" \
    -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
    -framework AppKit \
    -framework Carbon \
    Sources/*.swift \
    -o "$CACHE/StealthTicker-${arch}"
}

for arch in arm64 x86_64; do
  compile_slice "$arch"
done

lipo -create \
  "$CACHE/StealthTicker-arm64" \
  "$CACHE/StealthTicker-x86_64" \
  -output "$APP/Contents/MacOS/StealthTicker"

cp Info.plist "$APP/Contents/Info.plist"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
rm -rf "$CACHE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null || echo 1.0.0)"
echo "✅ 已生成 $(pwd)/$APP  (v$VERSION, $(lipo -archs "$APP/Contents/MacOS/StealthTicker"))"
echo "   运行：open $APP"
