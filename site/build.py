#!/usr/bin/env python3
"""Render the Vimdow website into site/dist.

Standard library only. One HTML template plus per-language JSON string files
produce one page per language, a sitemap, and the copied static assets.
The build fails on any key missing from, or unused by, a language file.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import shutil
import sys
from html.parser import HTMLParser
from pathlib import Path
from string import Template

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
CONTENT = SITE / "content"
TEMPLATES = SITE / "templates"
STATIC = SITE / "static"
MEDIA = SITE / "media"
DIST = SITE / "dist"
ICON_SOURCE = SITE / "artwork" / "favicon.svg"

HASHED_ASSETS = {"css": "style.css", "js": "demo.js", "statusline": "statusline.js"}
VOID_ELEMENTS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
    "meta", "source", "track", "wbr",
}
PLACEHOLDER = re.compile(r"\{\{\{\s*([\w.\-]+)\s*\}\}\}|\{\{\s*([\w.\-]+)\s*\}\}")


class BuildError(Exception):
    pass


def flatten(value: object, prefix: str = "") -> dict[str, str]:
    """Turn nested JSON objects into dotted keys with string leaves."""
    if isinstance(value, dict):
        out: dict[str, str] = {}
        for key, child in value.items():
            out.update(flatten(child, f"{prefix}{key}."))
        return out
    if isinstance(value, str):
        return {prefix[:-1]: value}
    raise BuildError(f"{prefix[:-1]}: strings must be text, got {type(value).__name__}")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise BuildError(f"{path.relative_to(ROOT)}: {error}") from None


class Strings:
    """A language's copy, with access tracking so unused keys fail the build."""

    def __init__(self, name: str, data: dict) -> None:
        self.name = name
        self.data = flatten(data)
        self.used: set[str] = set()

    def raw(self, key: str) -> str:
        """Trusted HTML fragment; only keys ending in _html may be used raw."""
        if not key.endswith("_html"):
            raise BuildError(f"{self.name}: {key} is plain text; use {{{{{key}}}}}")
        return self._lookup(key)

    def text(self, key: str) -> str:
        """HTML-escaped text."""
        if key.endswith("_html"):
            raise BuildError(f"{self.name}: {key} is HTML; use {{{{{{{key}}}}}}}")
        return html.escape(self._lookup(key), quote=True)

    def _lookup(self, key: str) -> str:
        if key not in self.data:
            raise BuildError(f"{self.name}: unknown key {key}")
        self.used.add(key)
        return self.data[key]

    def unused(self) -> list[str]:
        return sorted(set(self.data) - self.used)


def fragment(name: str) -> Template:
    return Template((TEMPLATES / f"{name}.html").read_text(encoding="utf-8").rstrip("\n"))


def render_keys(chords: list[list[str]]) -> str:
    rendered = []
    for chord in chords:
        caps = "".join(f"<kbd>{html.escape(key)}</kbd>" for key in chord)
        rendered.append(f'<span class="chord">{caps}</span>')
    return '<span class="or">/</span>'.join(rendered)


def render_template(template: str, strings: Strings, extras: dict[str, str]) -> str:
    """Replace {{key}} (escaped) and {{{key}}} (raw) placeholders."""

    def replace(match: re.Match) -> str:
        raw_key, text_key = match.group(1), match.group(2)
        key = raw_key or text_key
        if key.startswith("_."):
            if key not in extras:
                raise BuildError(f"template: unknown computed key {key}")
            return extras[key] if raw_key else html.escape(extras[key], quote=True)
        if key.startswith("site."):
            if raw_key:
                raise BuildError(f"template: {key} must be escaped")
            if key not in extras:
                raise BuildError(f"template: unknown site key {key}")
            return html.escape(extras[key], quote=True)
        return strings.raw(key) if raw_key else strings.text(key)

    return PLACEHOLDER.sub(replace, template)


class PageChecker(HTMLParser):
    """Checks tag balance and collects ids and internal references."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.ids: set[str] = set()
        self.refs: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if "id" in attributes and attributes["id"]:
            self.ids.add(attributes["id"])
        for name in ("href", "src", "poster"):
            value = attributes.get(name)
            if value:
                self.refs.append(value)
        if tag not in VOID_ELEMENTS:
            self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag in VOID_ELEMENTS:
            return
        if not self.stack or self.stack[-1] != tag:
            expected = self.stack[-1] if self.stack else "nothing"
            self.errors.append(f"line {self.getpos()[0]}: </{tag}> closes {expected}")
            return
        self.stack.pop()

    def finish(self) -> None:
        if self.stack:
            self.errors.append(f"unclosed tags: {' '.join(self.stack)}")


def check_page(path: Path, markup: str) -> PageChecker:
    checker = PageChecker()
    checker.feed(markup)
    checker.close()
    checker.finish()
    leftovers = PLACEHOLDER.findall(markup)
    if leftovers:
        checker.errors.append(f"unrendered placeholders: {leftovers}")
    if checker.errors:
        details = "\n  ".join(checker.errors)
        raise BuildError(f"{path.relative_to(SITE)}:\n  {details}")
    return checker


def content_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:8]


def check_language_keys(reference: Strings, strings: Strings) -> None:
    missing = sorted(set(reference.data) - set(strings.data))
    extra = sorted(set(strings.data) - set(reference.data))
    problems = []
    if missing:
        problems.append("missing keys: " + ", ".join(missing))
    if extra:
        problems.append("extra keys: " + ", ".join(extra))
    if problems:
        raise BuildError(f"{strings.name}: " + "; ".join(problems))


def head_tags(shared: dict, language: dict, strings: Strings, og_image_size: tuple[int, int]) -> str:
    site = shared["site"]
    base = site["url"]
    lines = [f'<link rel="canonical" href="{base}{language["path"]}">']
    for other in shared["languages"]:
        lines.append(f'<link rel="alternate" hreflang="{other["lang"]}" href="{base}{other["path"]}">')
    lines.append(f'<link rel="alternate" hreflang="x-default" href="{base}/">')
    lines += [
        '<meta property="og:type" content="website">',
        f'<meta property="og:site_name" content="{html.escape(site["name"])}">',
        f'<meta property="og:title" content="{strings.text("meta.title")}">',
        f'<meta property="og:description" content="{strings.text("meta.description")}">',
        f'<meta property="og:url" content="{base}{language["path"]}">',
        f'<meta property="og:image" content="{base}/og.png">',
        f'<meta property="og:image:width" content="{og_image_size[0]}">',
        f'<meta property="og:image:height" content="{og_image_size[1]}">',
        f'<meta property="og:locale" content="{language["ogLocale"]}">',
    ]
    for other in shared["languages"]:
        if other is not language:
            lines.append(f'<meta property="og:locale:alternate" content="{other["ogLocale"]}">')
    lines += [
        '<meta name="twitter:card" content="summary_large_image">',
        '<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#13161c">',
        '<meta name="theme-color" media="(prefers-color-scheme: light)" content="#ffffff">',
        '<link rel="icon" href="/icon.svg" type="image/svg+xml">',
        '<link rel="icon" href="/favicon.png" type="image/png" sizes="32x32">',
        '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
        f'<link rel="license" href="{site["license"]}">',
    ]
    return "\n".join(lines)


def font_tags(language: dict) -> str:
    """Preloads for the fonts above the fold, plus any language-only font stylesheets."""
    fonts = language["fonts"]
    lines = [
        f'<link rel="preload" href="{href}" as="font" type="font/woff2" crossorigin>'
        for href in fonts["preload"]
    ]
    for href in fonts["stylesheets"]:
        lines.append(f'<link rel="stylesheet" href="{href}?v={content_hash(STATIC / href.lstrip("/"))}">')
    return "\n".join(lines)


def json_ld(shared: dict, language: dict, strings: Strings) -> str:
    site = shared["site"]
    data = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": site["name"],
        "url": f"{site['url']}{language['path']}",
        "description": strings.data["meta.description"],
        "inLanguage": language["lang"],
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": "macOS 14 or later",
        "license": site["license"],
        "sameAs": site["repo"],
        "downloadUrl": site["download"],
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
    }
    return json_for_html(data)


def json_for_html(data: object) -> str:
    """JSON safe to embed inside a <script> element."""
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).replace("</", "<\\/")


def png_size(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise BuildError(f"{path.relative_to(SITE)}: not a PNG")
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def render_video(strings: Strings) -> str:
    """The real recording, shown only when site/media/demo.mp4 exists."""
    label = strings.text("demo.watchReal")
    fallback = strings.text("demo.videoUnsupported")
    if not (MEDIA / "demo.mp4").is_file():
        return ""
    sources = ""
    if (MEDIA / "demo.webm").is_file():
        sources += '<source src="/media/demo.webm" type="video/webm">'
    sources += '<source src="/media/demo.mp4" type="video/mp4">'
    poster = ' poster="/media/demo.jpg"' if (MEDIA / "demo.jpg").is_file() else ""
    return fragment("video").substitute(label=label, poster=poster, sources=sources, fallback=fallback)


def render_page(shared: dict, language: dict, strings: Strings, asset_urls: dict[str, str],
                og_image_size: tuple[int, int]) -> str:
    site = shared["site"]
    lang_link = fragment("lang_link")
    lang_links = "\n".join(
        lang_link.substitute(
            path=other["path"], lang=other["lang"], label=html.escape(other["label"]),
            current=' aria-current="page"' if other is language else "",
        )
        for other in shared["languages"]
    )
    how_step = fragment("how_step")
    how = "\n".join(
        how_step.substitute(title=strings.text(f"how.{step}.title"), text=strings.raw(f"how.{step}.text_html"))
        for step in shared["how"]
    )
    feature = fragment("feature")
    features = "\n".join(
        feature.substitute(title=strings.text(f"features.{name}.title"), text=strings.text(f"features.{name}.text"))
        for name in shared["features"]
    )
    cheat_row = fragment("cheat_row")
    cheats = "\n".join(
        cheat_row.substitute(keys=render_keys(row["keys"]), action=strings.text(f"cheat.rows.{row['id']}"))
        for row in shared["cheats"]
    )
    demo_step = fragment("demo_step")
    demo_steps = "\n".join(
        demo_step.substitute(id=html.escape(step["id"]), text=strings.text(f"demo.steps.{step['id']}"))
        for step in shared["demo"]["steps"]
    )
    extras = {
        "_.lang": language["lang"],
        "_.path": language["path"],
        "_.css": asset_urls["css"],
        "_.js": asset_urls["js"],
        "_.statuslineJs": asset_urls["statusline"],
        "_.fonts": font_tags(language),
        "_.helpFile": language["helpFile"],
        "_.head": head_tags(shared, language, strings, og_image_size),
        "_.jsonld": json_ld(shared, language, strings),
        "_.langLinks": lang_links,
        "_.how": how,
        "_.features": features,
        "_.cheats": cheats,
        "_.demoSteps": demo_steps,
        "_.demoConfig": json_for_html(shared["demo"]),
        "_.video": render_video(strings),
    }
    extras.update({f"site.{key}": value for key, value in site.items()})
    template = (TEMPLATES / "index.html").read_text(encoding="utf-8")
    return render_template(template, strings, extras)


def sitemap(shared: dict) -> str:
    base = shared["site"]["url"]
    urls = "\n".join(f"  <url><loc>{base}{language['path']}</loc></url>" for language in shared["languages"])
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{urls}\n</urlset>\n"
    )


def copy_tree(source: Path, target: Path) -> None:
    for path in sorted(source.rglob("*")):
        if path.name == ".gitkeep" or not path.is_file():
            continue
        destination = target / path.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)


def check_links(pages: dict[Path, PageChecker], shared: dict) -> None:
    """Every root-relative href/src must exist in dist; every #anchor in its page."""
    problems = []
    for path, checker in pages.items():
        for ref in checker.refs:
            target, _, anchor = ref.partition("#")
            target = target.split("?", 1)[0]
            if not target and anchor:
                if anchor not in checker.ids:
                    problems.append(f"{path.relative_to(DIST)}: missing anchor #{anchor}")
                continue
            if not target.startswith("/") or target.startswith("//"):
                continue
            candidate = DIST / target.lstrip("/")
            if candidate.is_dir():
                candidate = candidate / "index.html"
            if not candidate.is_file():
                problems.append(f"{path.relative_to(DIST)}: broken link {ref}")
    if problems:
        raise BuildError("\n".join(problems))


def build() -> None:
    shared = load_json(CONTENT / "_shared.json")
    languages = shared["languages"]
    reference_file = languages[0]["file"]
    reference = Strings(reference_file, load_json(CONTENT / f"{reference_file}.json"))
    if not ICON_SOURCE.is_file():
        raise BuildError(f"missing icon source {ICON_SOURCE.relative_to(ROOT)}")
    og_image_size = png_size(STATIC / "og.png")

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    copy_tree(STATIC, DIST)
    copy_tree(MEDIA, DIST / "media")
    shutil.copy2(ICON_SOURCE, DIST / "icon.svg")
    asset_urls = {key: f"/{name}?v={content_hash(STATIC / name)}" for key, name in HASHED_ASSETS.items()}

    pages: dict[Path, PageChecker] = {}
    for language in languages:
        strings = reference if language["file"] == reference_file else Strings(
            language["file"], load_json(CONTENT / f"{language['file']}.json")
        )
        check_language_keys(reference, strings)
        markup = render_page(shared, language, strings, asset_urls, og_image_size)
        unused = strings.unused()
        if unused:
            raise BuildError(f"{strings.name}: unused keys: {', '.join(unused)}")
        output = DIST / language["path"].strip("/") / "index.html"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(markup, encoding="utf-8")
        pages[output] = check_page(output, markup)

    (DIST / "sitemap.xml").write_text(sitemap(shared), encoding="utf-8")
    not_found = DIST / "404.html"
    if not_found.is_file():
        pages[not_found] = check_page(not_found, not_found.read_text(encoding="utf-8"))
    check_links(pages, shared)
    print(f"built {len(languages)} pages into {DIST.relative_to(ROOT)}")


def main() -> int:
    try:
        build()
    except BuildError as error:
        print(f"build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
