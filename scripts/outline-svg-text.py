#!/usr/bin/env python3
"""Replace SVG <text> set in the site's web fonts with outlined <path> elements.

librsvg on macOS finds fonts through Core Text and ignores font directories, so
the website's Iosevka and Pretendard (site/static/fonts) would silently fall
back to a system face. This converts each <text> whose first font-family is
Iosevka or Pretendard into a path, using the same font files the site serves:
Iosevka at 400 or 700, and the Pretendard variable subsets instanced at the
text's weight. Other text is left for librsvg to render with system fonts.
Only single-line text with plain character data is supported, and layout is the
sum of advance widths: Iosevka is monospaced without kerning, and Pretendard's
kerning, which only adjusts Latin pairs, is not applied.

Usage: outline-svg-text.py input.svg output.svg   (needs fonttools with brotli)
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SVG_NS = "http://www.w3.org/2000/svg"
FONTS_DIR = Path(__file__).resolve().parent.parent / "site" / "static" / "fonts"
IOSEVKA = {"400": "iosevka-400.woff2", "700": "iosevka-700.woff2"}
PRETENDARD = sorted((FONTS_DIR / "pretendard" / "woff2-dynamic-subset").glob("*.woff2"))
OUTLINED = ("Iosevka", "Pretendard")
INHERITED = ("font-family", "font-size", "font-weight", "text-anchor", "letter-spacing")
TEXT_ONLY = set(INHERITED) | {"x", "y"}

_iosevka: dict[str, TTFont] = {}
_cmaps: dict[Path, dict[int, str]] = {}
_instances: dict[tuple[Path, str], TTFont] = {}


def iosevka(weight: str) -> TTFont:
    if weight not in IOSEVKA:
        raise SystemExit(f"outline-svg-text: no Iosevka file for font-weight {weight}")
    if weight not in _iosevka:
        _iosevka[weight] = TTFont(FONTS_DIR / IOSEVKA[weight])
    return _iosevka[weight]


def pretendard(char: str, weight: str) -> TTFont | None:
    """The Pretendard subset that holds char, instanced at weight."""
    for path in PRETENDARD:
        if path not in _cmaps:
            _cmaps[path] = TTFont(path, lazy=True).getBestCmap()
        if ord(char) in _cmaps[path]:
            if (path, weight) not in _instances:
                subset = TTFont(path)
                instantiateVariableFont(subset, {"wght": float(weight)}, inplace=True)
                _instances[path, weight] = subset
            return _instances[path, weight]
    return None


def face(family: str, char: str, weight: str) -> TTFont:
    font = iosevka(weight) if family == "Iosevka" else pretendard(char, weight)
    if font is None or ord(char) not in font.getBestCmap():
        raise SystemExit(f"outline-svg-text: {family} has no glyph for {char!r}")
    return font


def number(value: str) -> str:
    return f"{value:.2f}".rstrip("0").rstrip(".")


def outline(text: ET.Element, style: dict[str, str]) -> ET.Element:
    if len(text):
        raise SystemExit("outline-svg-text: <tspan> and other children are not supported")
    family = style["font-family"].split(",")[0].strip()
    weight = style.get("font-weight", "400")
    size = float(style["font-size"])
    spacing = float(style.get("letter-spacing", "0"))

    glyphs = []
    for char in text.text or "":
        font = face(family, char, weight)
        name = font.getBestCmap()[ord(char)]
        scale = size / font["head"].unitsPerEm
        glyphs.append((font, name, scale, font["hmtx"][name][0] * scale + spacing))
    width = sum(advance for *_, advance in glyphs) - (spacing if glyphs else 0)

    x = float(text.get("x", "0"))
    y = float(text.get("y", "0"))
    anchor = style.get("text-anchor", "start")
    if anchor == "middle":
        x -= width / 2
    elif anchor == "end":
        x -= width

    commands = []
    for font, name, scale, advance in glyphs:
        glyph_set = font.getGlyphSet()
        pen = SVGPathPen(glyph_set, ntos=number)
        glyph_set[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, y)))
        commands.append(pen.getCommands())
        x += advance

    path = ET.Element(f"{{{SVG_NS}}}path", {k: v for k, v in text.attrib.items() if k not in TEXT_ONLY})
    path.set("d", " ".join(command for command in commands if command))
    path.tail = text.tail
    return path


def walk(element: ET.Element, inherited: dict[str, str]) -> None:
    style = dict(inherited)
    style.update({key: element.get(key) for key in INHERITED if element.get(key) is not None})
    for index, child in enumerate(list(element)):
        child_style = dict(style)
        child_style.update({key: child.get(key) for key in INHERITED if child.get(key) is not None})
        if child.tag == f"{{{SVG_NS}}}text" and child_style.get("font-family", "").split(",")[0].strip() in OUTLINED:
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
