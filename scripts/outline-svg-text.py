#!/usr/bin/env python3
"""Replace SVG <text> set in Iosevka with outlined <path> elements.

librsvg on macOS finds fonts through Core Text and ignores font directories, so
the website's Iosevka (site/static/fonts, subset to Latin) would silently fall
back to a system face. This converts each <text> whose font-family is Iosevka
into a path, using the same font files the site serves. Other text is left for
librsvg to render with system fonts. Only single-line text with plain character
data is supported; Iosevka is monospaced and has no kerning, so layout is the
sum of advance widths.

Usage: outline-svg-text.py input.svg output.svg   (needs fonttools with brotli)
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

SVG_NS = "http://www.w3.org/2000/svg"
FONTS_DIR = Path(__file__).resolve().parent.parent / "site" / "static" / "fonts"
FONT_FILES = {"400": "iosevka-400.woff2", "700": "iosevka-700.woff2"}
INHERITED = ("font-family", "font-size", "font-weight", "text-anchor", "letter-spacing")
TEXT_ONLY = set(INHERITED) | {"x", "y"}

_fonts: dict[str, TTFont] = {}


def font(weight: str) -> TTFont:
    if weight not in FONT_FILES:
        raise SystemExit(f"no Iosevka file for font-weight {weight}")
    if weight not in _fonts:
        _fonts[weight] = TTFont(FONTS_DIR / FONT_FILES[weight])
    return _fonts[weight]


def number(value: str) -> str:
    return f"{value:.2f}".rstrip("0").rstrip(".")


def outline(text: ET.Element, style: dict[str, str]) -> ET.Element:
    if len(text):
        raise SystemExit("outline-svg-text: <tspan> and other children are not supported")
    content = text.text or ""
    face = font(style.get("font-weight", "400"))
    cmap = face.getBestCmap()
    glyphs = face.getGlyphSet()
    size = float(style["font-size"])
    scale = size / face["head"].unitsPerEm
    spacing = float(style.get("letter-spacing", "0"))

    names = []
    for char in content:
        if ord(char) not in cmap:
            raise SystemExit(f"outline-svg-text: Iosevka subset has no glyph for {char!r}")
        names.append(cmap[ord(char)])
    advances = [face["hmtx"][name][0] * scale + spacing for name in names]
    width = sum(advances) - (spacing if names else 0)

    x = float(text.get("x", "0"))
    y = float(text.get("y", "0"))
    anchor = style.get("text-anchor", "start")
    if anchor == "middle":
        x -= width / 2
    elif anchor == "end":
        x -= width

    pen = SVGPathPen(glyphs, ntos=number)
    for name, advance in zip(names, advances):
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, y)))
        x += advance

    path = ET.Element(f"{{{SVG_NS}}}path", {k: v for k, v in text.attrib.items() if k not in TEXT_ONLY})
    path.set("d", pen.getCommands())
    path.tail = text.tail
    return path


def walk(element: ET.Element, inherited: dict[str, str]) -> None:
    style = dict(inherited)
    style.update({key: element.get(key) for key in INHERITED if element.get(key) is not None})
    for index, child in enumerate(list(element)):
        child_style = dict(style)
        child_style.update({key: child.get(key) for key in INHERITED if child.get(key) is not None})
        if child.tag == f"{{{SVG_NS}}}text" and child_style.get("font-family", "").split(",")[0].strip() == "Iosevka":
            element.remove(child)
            element.insert(index, outline(child, child_style))
        else:
            walk(child, style)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.parse(sys.argv[1])
    walk(tree.getroot(), {})
    tree.write(sys.argv[2], encoding="unicode")
    return 0


if __name__ == "__main__":
    sys.exit(main())
