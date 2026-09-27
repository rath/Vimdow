#!/usr/bin/env bash
# Download the website's web fonts into site/static/fonts.
# Iosevka and Iosevka Aile are subset to the characters the site uses;
# Pretendard (Korean page only) keeps its upstream dynamic subsets unmodified,
# as its license reserves the font name for unmodified files.
# Requires curl and fonttools with brotli: pip install fonttools brotli
set -euo pipefail

if ! command -v pyftsubset >/dev/null 2>&1; then
  echo "pyftsubset not found; install fonttools (pip install fonttools brotli)" >&2
  exit 1
fi

fontsource_version="5.3.0"
pretendard_version="1.3.9"
cdn="https://cdn.jsdelivr.net/npm"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fonts="$root/site/static/fonts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ASCII, Latin-1, general punctuation, arrows, and the modifier-key symbols.
unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-2193,U+21E7,U+2303,U+2318,U+2325,U+238B"

subset() {
  local family="$1" weight="$2" features="$3"
  curl -fsSL -o "$work/$family-$weight.woff2" \
    "$cdn/@fontsource/$family@$fontsource_version/files/$family-latin-$weight-normal.woff2"
  pyftsubset "$work/$family-$weight.woff2" --unicodes="$unicodes" --layout-features="$features" \
    --no-hinting --desubroutinize --flavor=woff2 --output-file="$fonts/$family-$weight.woff2"
}

rm -rf "$fonts"
mkdir -p "$fonts/pretendard/woff2-dynamic-subset"

subset iosevka 400 ""
subset iosevka 700 ""
subset iosevka-aile 400 "kern"
curl -fsSL -o "$fonts/LICENSE-Iosevka.txt" "$cdn/@fontsource/iosevka@$fontsource_version/LICENSE"

pretendard="$cdn/pretendard@$pretendard_version/dist"
curl -fsSL -o "$fonts/pretendard/pretendardvariable-dynamic-subset.css" \
  "$pretendard/web/variable/pretendardvariable-dynamic-subset.css"
curl -fsSL -o "$fonts/pretendard/LICENSE.txt" "$pretendard/LICENSE.txt"
grep -o 'PretendardVariable\.subset\.[0-9]*\.woff2' "$fonts/pretendard/pretendardvariable-dynamic-subset.css" |
  sort -u | while read -r file; do
    curl -fsSL -o "$fonts/pretendard/woff2-dynamic-subset/$file" \
      "$pretendard/web/variable/woff2-dynamic-subset/$file"
  done

echo "wrote Iosevka, Iosevka Aile, and Pretendard into site/static/fonts"
