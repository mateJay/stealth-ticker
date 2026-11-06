#!/bin/bash
# 打包成 DMG：./scripts/create-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="dist/StealthTicker-$VERSION.dmg"

./build.sh

rm -rf dist
mkdir -p dist/staging
cp -R StealthTicker.app dist/staging/
ln -s /Applications dist/staging/Applications

hdiutil create \
  -volname "StealthTicker" \
  -srcfolder dist/staging \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf dist/staging
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
