#!/bin/zsh
# 发布新版本：scripts/release.sh 1.3.0 path/to/notes.md
#
# 1. 构建并打包 DMG
# 2. 用钥匙串中的 Sparkle 私钥签名
# 3. 打 tag、创建 GitHub Release 并上传 DMG
# 4. 更新 appcast.xml 并推送（在 DMG 可下载之后，避免用户检查到无法下载的更新）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: scripts/release.sh <版本号> <发布说明.md>}"
NOTES="${2:?用法: scripts/release.sh <版本号> <发布说明.md>}"
REPO="WinglokWong/TaskBoard"
TAG="v${VERSION}"
DMG="build/TaskBoard-${VERSION}.dmg"
GH="$(command -v gh || echo "$HOME/.local/bin/gh")"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

[[ -f "$NOTES" ]] || { echo "找不到发布说明: $NOTES"; exit 1; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || { echo "请在 main 分支上发布"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "工作区有未提交的改动，请先提交"; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "标签 $TAG 已存在"; exit 1; }

# Sparkle 用 CFBundleVersion 比较新旧版本，必须单调递增：使用提交数
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "▶︎ 构建 ${VERSION} (build ${BUILD_NUMBER})"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" scripts/package_dmg.sh

echo "▶︎ 签名更新包"
SIGNATURE_ATTRS="$("$SIGN_UPDATE" "$DMG")"   # 输出形如：sparkle:edSignature="…" length="…"

echo "▶︎ 发布 GitHub Release"
git tag -a "$TAG" -m "TaskBoard ${VERSION}"
git push -q origin "$TAG"
"$GH" release create "$TAG" "$DMG" --repo "$REPO" --title "TaskBoard ${VERSION}" --notes-file "$NOTES"

echo "▶︎ 更新 appcast.xml"
NOTES_HTML="$("$GH" api markdown -f mode=gfm -f context="$REPO" -F text=@"$NOTES")"
python3 scripts/update_appcast.py appcast.xml \
    --version "$VERSION" --build "$BUILD_NUMBER" \
    --url "https://github.com/${REPO}/releases/download/${TAG}/TaskBoard-${VERSION}.dmg" \
    --notes-link "https://github.com/${REPO}/releases/tag/${TAG}" \
    --signature-attrs "$SIGNATURE_ATTRS" \
    --notes-html "$NOTES_HTML"
git add appcast.xml
git commit -q -m "Update appcast for ${VERSION}"
git push -q origin main

echo "✅ 已发布 ${VERSION}: https://github.com/${REPO}/releases/tag/${TAG}"
