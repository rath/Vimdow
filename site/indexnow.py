#!/usr/bin/env python3
"""Tell the IndexNow search engines that the website's pages have changed.

Bing, Naver, Yandex, and the other IndexNow engines share each submission.
Google does not take part; it finds changes through sitemap.xml. The key comes
from site/content/_shared.json, and the build publishes it at /<key>.txt so the
engines can confirm the site owns it. The deploy workflow runs this after each
deploy. Standard library only.

Usage: indexnow.py [--dry-run]
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ENDPOINT = "https://api.indexnow.org/indexnow"
SHARED = Path(__file__).resolve().parent / "content" / "_shared.json"


def main() -> int:
    if sys.argv[1:] not in ([], ["--dry-run"]):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    shared = json.loads(SHARED.read_text(encoding="utf-8"))
    site = shared["site"]
    key = site["indexNowKey"]
    payload = {
        "host": site["url"].split("://", 1)[1],
        "key": key,
        "keyLocation": f"{site['url']}/{key}.txt",
        "urlList": [f"{site['url']}{language['path']}" for language in shared["languages"]],
    }
    if sys.argv[1:] == ["--dry-run"]:
        print(json.dumps(payload, indent=2))
        return 0

    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    except urllib.error.URLError as error:
        print(f"::warning::IndexNow was unreachable ({error.reason}); the engines will still crawl the sitemap")
        return 0
    if status in (200, 202):
        print(f"IndexNow accepted {len(payload['urlList'])} URLs (HTTP {status})")
        return 0
    if status == 429 or status >= 500:
        print(f"::warning::IndexNow is busy (HTTP {status}); the engines will still crawl the sitemap")
        return 0
    print(f"IndexNow rejected the submission (HTTP {status}); check {payload['keyLocation']}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
