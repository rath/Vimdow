#!/bin/bash
set -euo pipefail

# Renders the AppIcon asset catalog PNGs from the SVG sources in Artwork/.
# 16 and 32 px slots use launcher-small.svg; larger slots use launcher.svg.

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FULL_ICON="$REPO_ROOT/Artwork/launcher.svg"
readonly SMALL_ICON="$REPO_ROOT/Artwork/launcher-small.svg"
readonly ICON_SET="$REPO_ROOT/VimdowManager/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Missing rsvg-convert (librsvg); see README.md." >&2
  exit 1
fi

render() {
  local svg="$1" pixels="$2" name="$3"
  rsvg-convert --width "$pixels" --height "$pixels" \
    --output "$ICON_SET/$name" "$svg"
}

render "$SMALL_ICON" 16 icon_16x16.png
render "$SMALL_ICON" 32 icon_16x16@2x.png
render "$SMALL_ICON" 32 icon_32x32.png
render "$FULL_ICON" 64 icon_32x32@2x.png
render "$FULL_ICON" 128 icon_128x128.png
render "$FULL_ICON" 256 icon_128x128@2x.png
render "$FULL_ICON" 256 icon_256x256.png
render "$FULL_ICON" 512 icon_256x256@2x.png
render "$FULL_ICON" 512 icon_512x512.png
render "$FULL_ICON" 1024 icon_512x512@2x.png

version="$(rsvg-convert --version)"
echo "Rendered $ICON_SET with ${version%%$'\n'*}."
