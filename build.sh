#!/bin/zsh
# 构建 TaskBoard.app 到 build/ 目录
# （Finder 和程序坞中按语言显示为「任务看板」「任務看板」或「TaskBoard」）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TaskBoard"
APP="build/${APP_NAME}.app"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# Sparkle 自动更新
FEED_URL="https://raw.githubusercontent.com/WinglokWong/TaskBoard/main/appcast.xml"
# 对应的私钥保存在发布者 Mac 的钥匙串中（由 Sparkle 的 generate_keys 生成）
SPARKLE_PUBLIC_KEY="V6Hnh6QMxTCvrzGMeJ/bKPGEWckUPTwP3eoqd6n7aBQ="

# 通用二进制：同时支持 Apple Silicon 和 Intel
ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}"
PRODUCTS="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/TaskBoard" "$APP/Contents/MacOS/TaskBoard"
# 嵌入 Sparkle.framework（ditto 保留框架内的符号链接）
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TaskBoard"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"

# 本地化：编译字符串目录，并复制各语言的 InfoPlist.strings（应用名称）
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
# 源语言（简体中文）也需要一份字符串表，否则会退回到英文
python3 scripts/source_strings.py Resources/Localizable.xcstrings "$APP/Contents/Resources/zh-Hans.lproj"
for lproj in Resources/*.lproj; do
    mkdir -p "$APP/Contents/Resources/$(basename "$lproj")"
    cp "$lproj"/* "$APP/Contents/Resources/$(basename "$lproj")/"
done
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>local.taskboard</string>
    <key>CFBundleExecutable</key><string>TaskBoard</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
    <key>LSHasLocalizedDisplayName</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>local.taskboard.card</string>
            <key>UTTypeDescription</key><string>TaskBoard Card</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>local.taskboard.column</string>
            <key>UTTypeDescription</key><string>TaskBoard List</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>local.taskboard.archive</string>
            <key>UTTypeDescription</key><string>TaskBoard Export</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
            <key>UTTypeIconFile</key><string>AppIcon</string>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>taskboard</string></array></dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>TaskBoard Export</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>local.taskboard.archive</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 先签名框架，再签名应用（临时签名）
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "✅ 已生成: $(pwd)/$APP"
