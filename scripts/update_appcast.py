#!/usr/bin/env python3
"""在 Sparkle 的 appcast.xml 最前面加入一个新版本条目（文件不存在时创建）。"""
import argparse
import os
import re
from email.utils import formatdate

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>TaskBoard</title>
    <link>https://github.com/WinglokWong/TaskBoard</link>
    <description>TaskBoard updates</description>
    <language>zh-cn</language>
"""
FOOTER = """  </channel>
</rss>
"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("appcast")
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--notes-link", required=True)
    p.add_argument("--signature-attrs", required=True, help='sign_update 的输出：sparkle:edSignature="…" length="…"')
    p.add_argument("--notes-html", required=True)
    p.add_argument("--min-system", default="14.0")
    a = p.parse_args()

    sig = re.search(r'sparkle:edSignature="([^"]+)"', a.signature_attrs)
    length = re.search(r'length="(\d+)"', a.signature_attrs)
    if not sig or not length:
        raise SystemExit(f"无法解析签名信息: {a.signature_attrs}")

    notes_html = a.notes_html.replace("]]>", "]]]]><![CDATA[>")
    item = f"""    <item>
      <title>Version {a.version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{a.build}</sparkle:version>
      <sparkle:shortVersionString>{a.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{a.min_system}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{a.notes_link}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes_html}]]></description>
      <enclosure url="{a.url}" sparkle:edSignature="{sig.group(1)}" length="{length.group(1)}" type="application/octet-stream"/>
    </item>
"""

    if os.path.exists(a.appcast):
        content = open(a.appcast, encoding="utf-8").read()
        marker = content.find("    <item>")
        if marker == -1:
            marker = content.find("  </channel>")
        if marker == -1:
            raise SystemExit("appcast.xml 格式不正确")
        content = content[:marker] + item + content[marker:]
    else:
        content = HEADER + item + FOOTER

    with open(a.appcast, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"appcast.xml: 已加入 {a.version} (build {a.build})")


if __name__ == "__main__":
    main()
