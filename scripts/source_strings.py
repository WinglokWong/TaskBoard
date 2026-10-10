#!/usr/bin/env python3
"""为源语言（简体中文）生成 Localizable.strings。

xcstringstool 只为翻译语言生成字符串表，不生成源语言的表。没有简体中文表时，
系统在简体中文环境下查找字符串会退回到开发语言（英文），导致部分文字显示成英文。
这里把每个键原样写成简体中文的值。

用法：python3 scripts/source_strings.py Resources/Localizable.xcstrings 输出目录/zh-Hans.lproj
"""
import json
import os
import plistlib
import sys

catalog_path, out_dir = sys.argv[1], sys.argv[2]
catalog = json.load(open(catalog_path, encoding="utf-8"))
table = {key: key for key, entry in catalog["strings"].items()
         if key and entry.get("extractionState") != "stale"}
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "Localizable.strings"), "wb") as f:
    plistlib.dump(table, f, fmt=plistlib.FMT_XML, sort_keys=True)
print(f"zh-Hans: {len(table)} strings")
