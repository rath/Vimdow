#!/bin/bash
set -euo pipefail

readonly XCODEGEN_VERSION="2.46.0"
readonly COCOAPODS_VERSION="1.16.2"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in xcodegen pod; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing $tool. Install XcodeGen $XCODEGEN_VERSION and CocoaPods $COCOAPODS_VERSION; see README.md." >&2
    exit 1
  fi
done

if [[ "$(xcodegen --version)" != "Version: $XCODEGEN_VERSION" ]]; then
  echo "XcodeGen $XCODEGEN_VERSION is required; see README.md for installation." >&2
  exit 1
fi
if [[ "$(pod --version)" != "$COCOAPODS_VERSION" ]]; then
  echo "CocoaPods $COCOAPODS_VERSION is required; see README.md for installation." >&2
  exit 1
fi

cd "$REPO_ROOT"
xcodegen generate
pod install

echo "Open $REPO_ROOT/VimdowManager.xcworkspace to build and run."
