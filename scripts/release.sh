#!/bin/bash
set -euo pipefail

# Builds a notarized Vimdow.app from a clean HEAD, zips it as
# build/release/Vimdow.zip, and tags the commit v<MARKETING_VERSION>.
#
#   scripts/release.sh                 release the version in project.yml
#   scripts/release.sh patch|minor|major|X.Y.Z
#                                      raise MARKETING_VERSION, add 1 to
#                                      CURRENT_PROJECT_VERSION, commit, release
#
# Needs a Developer ID Application certificate in the keychain and a notarytool
# keychain profile (NOTARY_PROFILE, default "vimdow-notary"); see README.md.
# Publishing stays manual: the script prints the push and draft-release commands.

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-vimdow-notary}"
readonly OUT="$REPO_ROOT/build/release"
readonly ARCHIVE="$OUT/VimdowManager.xcarchive"
readonly APP="$OUT/export/Vimdow.app"
readonly ZIP="$OUT/Vimdow.zip"
readonly SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'

fail() {
  echo "$*" >&2
  exit 1
}

setting() {
  sed -n "s/^ *$1: \"\(.*\)\"\$/\1/p" project.yml
}

cd "$REPO_ROOT"

if (($# > 1)); then
  fail "Usage: scripts/release.sh [patch|minor|major|X.Y.Z]"
fi
if [[ -n "$(git status --porcelain)" ]]; then
  fail "The working tree has changes. Release from a clean, committed HEAD."
fi

version="$(setting MARKETING_VERSION)"
build="$(setting CURRENT_PROJECT_VERSION)"
if [[ ! "$version" =~ $SEMVER || ! "$build" =~ ^[1-9][0-9]*$ ]]; then
  fail "project.yml needs MARKETING_VERSION like 1.2.3 and a positive CURRENT_PROJECT_VERSION."
fi

bump="${1:-}"
if [[ -n "$bump" ]]; then
  IFS=. read -r major minor patch <<<"$version"
  case "$bump" in
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
    *)
      [[ "$bump" =~ $SEMVER ]] || fail "Usage: scripts/release.sh [patch|minor|major|X.Y.Z]"
      next="$bump"
      ;;
  esac
  if [[ "$next" == "$version" \
    || "$(printf '%s\n' "$version" "$next" | sort -V | tail -n 1)" != "$next" ]]; then
    fail "$next is not newer than the current version $version."
  fi
  version="$next"
  build="$((build + 1))"
fi

readonly TAG="v$version"
if tagged="$(git rev-parse -q --verify "refs/tags/$TAG^{commit}")" \
  && { [[ -n "$bump" ]] || [[ "$tagged" != "$(git rev-parse HEAD)" ]]; }; then
  fail "$TAG already exists. Pass patch, minor, or major to release a new version."
fi

identities="$(security find-identity -v -p codesigning \
  | grep '"Developer ID Application: ' || true)"
if [[ -z "$identities" || "$(wc -l <<<"$identities")" -ne 1 ]]; then
  fail "Expected exactly one Developer ID Application certificate; see README.md."
fi
team_id="$(sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/' <<<"$identities")"

if [[ -n "$bump" ]]; then
  sed -i '' -E \
    -e "s/^( *MARKETING_VERSION: )\".*\"\$/\\1\"$version\"/" \
    -e "s/^( *CURRENT_PROJECT_VERSION: )\".*\"\$/\\1\"$build\"/" project.yml
  git commit -q -m "chore(release): bump version to $version" \
    -m "- Set MARKETING_VERSION to $version and CURRENT_PROJECT_VERSION to $build" \
    -- project.yml
  trap '[[ $? -eq 0 ]] || echo "The version bump to $version is committed." \
    "After fixing the problem, rerun scripts/release.sh without an argument." >&2' EXIT
fi

./scripts/setup.sh
xcodebuild -project VimdowManager.xcodeproj -scheme VimdowCore \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -quiet test

rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project VimdowManager.xcodeproj -scheme VimdowManager \
  -configuration Release -derivedDataPath "$OUT/DerivedData" \
  -archivePath "$ARCHIVE" -onlyUsePackageVersionsFromResolvedFile -quiet archive

cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>teamID</key>
	<string>$team_id</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet

built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")"
built_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$APP/Contents/Info.plist")"
if [[ "$built_version" != "$version" || "$built_number" != "$build" ]]; then
  fail "The app reports $built_version ($built_number), not $version ($build)."
fi
if [[ "$(lipo -archs "$APP/Contents/MacOS/Vimdow")" != "x86_64 arm64" ]]; then
  echo "The app is not a universal (x86_64 and arm64) binary." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
signature="$(codesign -dvv "$APP" 2>&1)"
if ! grep -q '^Authority=Developer ID Application: ' <<<"$signature" \
  || ! grep -q '^CodeDirectory .*flags=.*runtime' <<<"$signature"; then
  echo "The app is not signed with Developer ID and the hardened runtime." >&2
  exit 1
fi

ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
submission="$(xcrun notarytool submit "$OUT/notarize.zip" \
  --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
rm "$OUT/notarize.zip"
status="$(plutil -extract status raw -o - - <<<"$submission")"
if [[ "$status" != "Accepted" ]]; then
  submission_id="$(plutil -extract id raw -o - - <<<"$submission")"
  echo "Notarization finished with status $status. Apple's log:" >&2
  xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" >&2
  exit 1
fi
xcrun stapler staple -q "$APP"
xcrun stapler validate -q "$APP"
spctl --assess --type execute "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
checksum="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
if [[ -z "${tagged:-}" ]]; then
  git tag -a "$TAG" -m "Vimdow $version"
fi

cat <<DONE

Built ${ZIP#"$REPO_ROOT/"} for Vimdow $version ($build), notarized and tagged $TAG.
SHA-256: $checksum

To publish a draft release:
  git push origin HEAD $TAG
  gh release create $TAG ${ZIP#"$REPO_ROOT/"} --draft --verify-tag \\
    --title "Vimdow $version" --generate-notes
DONE
