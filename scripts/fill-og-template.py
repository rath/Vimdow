#!/usr/bin/env python3
"""Fill site/artwork/og.svg once per website language.

The template's placeholders come from the language's entry in
site/content/_shared.json (help file name, tab label), its content file (help
line, tagline), and site/artwork/og.json (font, tab geometry, headline line
breaks, per-line tracking, subtitle). Kana lines are tracked tighter by hand
because librsvg ignores font-feature-settings, so the site's "palt" is unavailable. The headline lines must join to the page's hero.tagline.

Each filled SVG is written beside the template as .og-<file>.svg, so its
relative image reference resolves, and one line per language is printed:
<filled svg path> TAB <PNG file name in site/static>.

Usage: fill-og-template.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from string import Template
from xml.sax.saxutils import escape

SITE = Path(__file__).resolve().parent.parent / "site"
ARTWORK = SITE / "artwork"
TAB_START = 160
TAB_GAP = 2
LINE_HEIGHT = 108
FIRST_BASELINE = 250


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def tabs(languages: list[dict], og: dict, current: dict) -> str:
    """The language tabs, with the current page's tab selected as on the site."""
    backgrounds, labels, underlines = [], [], []
    x = TAB_START
    for language in languages:
        tab = og[language["file"]]["tab"]
        width = tab["width"]
        selected = language is current
        backgrounds.append(f'<rect x="{x}" y="0" width="{width}" height="52" fill="{"#FFFFFF" if selected else "#D5DAE0"}"/>')
        labels.append(
            f'<text x="{x + width / 2:g}" y="{tab["baseline"]}" font-family="{og[language["file"]]["font"]}"'
            f' font-weight="{700 if selected else 400}" font-size="{tab["size"]}" text-anchor="middle"'
            f' fill="#13161C">{escape(language["label"])}</text>'
        )
        if not selected:
            underlines.append(f'<rect x="{x + 14}" y="38" width="{width - 28}" height="1.5" fill="#13161C"/>')
        x += width + TAB_GAP
    return "\n".join(f"  {line}" for line in backgrounds + labels + underlines)


def main() -> int:
    if len(sys.argv) != 1:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    template = Template((ARTWORK / "og.svg").read_text(encoding="utf-8"))
    og = load(ARTWORK / "og.json")
    languages = load(SITE / "content" / "_shared.json")["languages"]
    for language in languages:
        page = og[language["file"]]
        copy = load(SITE / "content" / f"{language['file']}.json")["hero"]
        headline = page["headline"]
        if "".join(headline["lines"]).replace(" ", "") != copy["tagline"].replace(" ", ""):
            raise SystemExit(f"og.json: the {language['file']} headline lines no longer spell hero.tagline")
        tracking = headline.get("letterSpacing", [0] * len(headline["lines"]))
        lines = "\n".join(
            f'    <text x="{headline["x"]}" y="{FIRST_BASELINE + index * LINE_HEIGHT}"'
            + (f' letter-spacing="{spacing}"' if spacing else "")
            + f">{escape(line)}</text>"
            for index, (line, spacing) in enumerate(zip(headline["lines"], tracking, strict=True))
        )
        filled = template.substitute(
            tabs=tabs(languages, og, language),
            helpFile=escape(language["helpFile"]),
            helpLine=escape(copy["helpLine"]),
            font=page["font"],
            headlineSize=headline["size"],
            headline=lines,
            subtitle=escape(page["subtitle"]),
        )
        output = ARTWORK / f".og-{language['file']}.svg"
        output.write_text(filled, encoding="utf-8")
        print(f"{output}\t{language['ogImage'].lstrip('/')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
