#!/bin/zsh
# 构建通用版本并打包为 DMG：VERSION=1.0.0 scripts/package_dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
export VERSION
./build.sh

APP="build/任务看板.app"
DMG="build/TaskBoard-${VERSION}.dmg"
STAGING="build/dmg-staging"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "TaskBoard ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "✅ 已生成: $(pwd)/$DMG"
