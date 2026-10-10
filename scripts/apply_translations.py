#!/usr/bin/env python3
"""把 scripts/translations.py 中的翻译写入 Resources/Localizable.xcstrings，并报告缺失的翻译。"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from translations import T  # noqa: E402

CATALOG = os.path.join(os.path.dirname(__file__), "..", "Resources", "Localizable.xcstrings")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
    return unit(value)


catalog = json.load(open(CATALOG, encoding="utf-8"))
missing = []
for key, entry in catalog["strings"].items():
    if entry.get("extractionState") == "stale":
        continue
    if key not in T:
        missing.append(key)
        continue
    en, hant = T[key]
    entry["localizations"] = {"en": localization(en), "zh-Hant": localization(hant)}

unused = [k for k in T if k not in catalog["strings"]]
with open(CATALOG, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")

print(f"{len(catalog['strings']) - len(missing)} translated, {len(missing)} missing, {len(unused)} unused")
for key in missing:
    print("  MISSING:", json.dumps(key, ensure_ascii=False))
for key in unused:
    print("  unused: ", json.dumps(key, ensure_ascii=False))
sys.exit(1 if missing else 0)
