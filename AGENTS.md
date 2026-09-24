# Agent workflow

## Project

- Native macOS AppKit app, Swift 6, minimum macOS 14.
- Use Xcode 27.0 and XcodeGen 2.46.0. Dependencies use Swift Package Manager;
  CocoaPods and the old root `.xcworkspace` are unused.
- Edit `project.yml`, not the generated `.xcodeproj`. Keep the root
  `Package.resolved` tracked; generated projects and `DerivedData/` are ignored.
- Command logic and geometry live in `Sources/VimdowCore/`; Accessibility,
  shortcuts, and UI live in `VimdowManager/`.
- The app icon comes from `Artwork/launcher.svg` and, for 16 and 32 px,
  `Artwork/launcher-small.svg`. After editing either, run
  `./scripts/generate-app-icon.sh`; never edit the asset catalog PNGs by hand.

## Build and test

Run commands from the repository root. On a fresh checkout, after adding/removing
source files, or after changing project configuration, generate the project:

```sh
./scripts/setup.sh
```

Build the app for local installation:

```sh
xcodebuild -project VimdowManager.xcodeproj -scheme VimdowManager \
  -configuration Release -derivedDataPath DerivedData \
  -onlyUsePackageVersionsFromResolvedFile build
```

Use `-configuration Debug` for a host-architecture development build. Release
includes both arm64 and x86_64. Do not run builds and tests concurrently against
the same `DerivedData` directory.

For command or geometry changes, run the core tests:

```sh
xcodebuild -project VimdowManager.xcodeproj -scheme VimdowCore \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -onlyUsePackageVersionsFromResolvedFile test
```

For shortcut or search-panel changes, use the same test command with scheme
`VimdowShortcuts` or `VimdowPresentation`, respectively. These require an
interactive Mac; quit Vimdow before shortcut tests to avoid registration conflicts.
For documentation-only changes, `git diff --check` is sufficient.

## Local signing

- Preserve the existing ignored `Config/Signing.local.xcconfig`. Both build
  configurations use it automatically; do not override signing on the command line.
- Keep the same Apple Development certificate, bundle ID
  (`rath.toys.VimdowManager`), and installed path across rebuilds so Accessibility
  permission can normally persist. Ad-hoc builds do not provide this continuity.
- If local signing is not configured, follow README's signing instructions.
  Select the certificate by SHA-1 fingerprint; names can match expired certificates.
- Never commit personal certificate fingerprints, Team IDs, or the local signing
  file. Public defaults and the example configuration must remain generic.

## Install for manual testing

1. Build successfully, then verify
   `DerivedData/Build/Products/Release/VimdowManager.app` with
   `codesign --verify --deep --strict <app-path>`.
2. For an existing installation, compare `codesign -dr- <app-path>` for the new
   and installed bundles. An unchanged designated requirement preserves signing
   continuity; investigate an unexpected difference before replacing the app.
3. Copy the new bundle with `ditto` into a temporary staging directory under
   `/Applications`. Quit the running `/Applications/VimdowManager.app` and wait
   for its process to exit before replacing it.
4. Move the existing bundle to a temporary backup, then move the staged bundle
   to `/Applications/VimdowManager.app`. Verify its signature and compare its
   executable SHA-256 with the build. Restore the backup if installation fails;
   remove the temporary backup after successful verification.
5. Run `open /Applications/VimdowManager.app`. Avoid launching a second copy from
   `DerivedData` or Xcode during manual testing. Installation may require sandbox
   approval to write outside the repository.

Do not modify the TCC database. If Accessibility rejects the app despite an
enabled switch, have the user remove and re-add the installed app in System
Settings. A signing change may require this once.

Use `docs/testing.md` for manual checks: enter command mode with
Control–Option–A, test movement/resizing, `/` search with Korean input and
Enter/Escape, and Control–Option–K/L for display round trips. Automated tests do
not establish live Accessibility or multi-monitor behavior. Report what was
built, tested, and installed, and what still needs manual verification.
