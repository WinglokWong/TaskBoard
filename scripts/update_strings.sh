#!/bin/zsh
# 从源码提取界面文字，同步到 Resources/Localizable.xcstrings，并写入 scripts/translations.py 中的翻译。
# 修改了界面文字后运行；新增的文字需要先在 translations.py 中补上英文和繁体中文。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
touch Sources/TaskBoard/*.swift
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
args=()
for f in "$OUT"/*.stringsdata; do args+=(--stringsdata "$f"); done
xcrun xcstringstool sync Resources/Localizable.xcstrings "${args[@]}"
python3 scripts/apply_translations.py
