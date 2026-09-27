#!/usr/bin/env bash
# Render the website's raster images from their SVG sources in site/artwork.
# Requires rsvg-convert from librsvg (brew install librsvg) and fonttools with
# brotli (pip install fonttools brotli) to outline the Iosevka text in og.svg.
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found; install librsvg (brew install librsvg)" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artwork="$root/site/artwork"
static="$root/site/static"

# The outlined copy sits beside og.svg so its relative image reference resolves.
outlined="$artwork/.og.outlined.svg"
trap 'rm -f "$outlined"' EXIT
python3 "$root/scripts/outline-svg-text.py" "$artwork/og.svg" "$outlined"

rsvg-convert -w 1200 -h 630 "$outlined" -o "$static/og.png"
rsvg-convert -w 32 -h 32 "$artwork/favicon.svg" -o "$static/favicon.png"
rsvg-convert -w 180 -h 180 "$artwork/touch-icon.svg" -o "$static/apple-touch-icon.png"

echo "rendered og.png, favicon.png, apple-touch-icon.png into site/static"
