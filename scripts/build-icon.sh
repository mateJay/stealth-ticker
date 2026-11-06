#!/bin/bash
# 重新生成 AppIcon.icns（改了图标之后跑这个）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build-cache
swift -module-cache-path .build-cache scripts/make-icon.swift

rm -rf AppIcon.iconset
mkdir AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" AppIcon-1024.png --out "AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" AppIcon-1024.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns

rm -rf AppIcon.iconset AppIcon-1024.png
echo "✅ AppIcon.icns"
