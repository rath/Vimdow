#!/usr/bin/env bash
# Render the website's raster images from their SVG sources.
# Requires rsvg-convert from librsvg: brew install librsvg
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found; install librsvg (brew install librsvg)" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
static="$root/site/static"

rsvg-convert -w 1200 -h 630 "$root/site/artwork/og.svg" -o "$static/og.png"
rsvg-convert -w 32 -h 32 "$root/Artwork/launcher-small.svg" -o "$static/favicon.png"
rsvg-convert -w 180 -h 180 "$root/Artwork/launcher.svg" -o "$static/apple-touch-icon.png"

echo "rendered og.png, favicon.png, apple-touch-icon.png into site/static"
