#!/bin/bash
set -euo pipefail

readonly XCODEGEN_VERSION="2.46.0"
readonly XCODE_VERSION="Xcode 27.0"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_LOCK="$REPO_ROOT/VimdowManager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Missing XcodeGen $XCODEGEN_VERSION; see README.md." >&2
  exit 1
fi
if [[ "$(xcodegen --version)" != "Version: $XCODEGEN_VERSION" ]]; then
  echo "XcodeGen $XCODEGEN_VERSION is required; see README.md." >&2
  exit 1
fi
if [[ "$(xcodebuild -version | head -n 1)" != "$XCODE_VERSION" ]]; then
  echo "$XCODE_VERSION is required. Select it with xcode-select or DEVELOPER_DIR." >&2
  exit 1
fi

cd "$REPO_ROOT"
xcodegen generate
mkdir -p "$(dirname "$PROJECT_LOCK")"
cp Package.resolved "$PROJECT_LOCK"
xcodebuild -resolvePackageDependencies -project VimdowManager.xcodeproj \
  -scheme VimdowManager -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile

if ! cmp -s Package.resolved "$PROJECT_LOCK"; then
  echo "The resolved dependencies changed. Review project.yml and Package.resolved together." >&2
  exit 1
fi

echo "Open $REPO_ROOT/VimdowManager.xcodeproj to build and run."
