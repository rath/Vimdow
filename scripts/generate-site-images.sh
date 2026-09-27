#!/usr/bin/env bash
# Render the website's raster images from their SVG sources in site/artwork.
# Requires rsvg-convert from librsvg (brew install librsvg) and fonttools with
# brotli (pip install fonttools brotli) to outline the site's web fonts in the
# social previews. Japanese and Chinese preview text uses the macOS system fonts
# Hiragino Sans and PingFang SC.
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found; install librsvg (brew install librsvg)" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artwork="$root/site/artwork"
static="$root/site/static"

# One social preview per language, filled from og.svg and og.json. The filled
# and outlined copies sit beside og.svg so its relative image reference resolves.
trap 'rm -f "$artwork"/.og-*.svg' EXIT
previews="$(python3 "$root/scripts/fill-og-template.py")"
rendered=()
while IFS=$'\t' read -r filled png; do
  outlined="${filled%.svg}.outlined.svg"
  python3 "$root/scripts/outline-svg-text.py" "$filled" "$outlined"
  rsvg-convert -w 1200 -h 630 "$outlined" -o "$static/$png"
  rendered+=("$png")
done <<<"$previews"

rsvg-convert -w 32 -h 32 "$artwork/favicon.svg" -o "$static/favicon.png"
rsvg-convert -w 180 -h 180 "$artwork/touch-icon.svg" -o "$static/apple-touch-icon.png"

echo "rendered ${rendered[*]}, favicon.png, apple-touch-icon.png into site/static"
