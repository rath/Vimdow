# About Vimdow

Vimdow is a window management application for macOS.

# Development

The app requires macOS 12.4 or later. Building requires Xcode with its command
line tools selected, XcodeGen **2.46.0**, and CocoaPods **1.16.2**.

Install XcodeGen from its [2.46.0 release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)
and put `xcodegen` on your `PATH`. With a Ruby environment installed, install
CocoaPods using:

```sh
gem install cocoapods -v 1.16.2
```

Generate the project and install the locked dependencies:

```sh
./scripts/setup.sh
open VimdowManager.xcworkspace
```

The setup script checks tool versions, runs XcodeGen, then runs `pod install`.
It can be invoked from any directory and stops if a step fails. It does not
install tools automatically.

`project.yml` is the source of truth for project settings. Generated Xcode
projects, workspaces, and Pods are ignored by Git. Edit project settings in
the YAML and rerun setup after changing settings or adding/removing source
files. Settings changed only in Xcode are overwritten on regeneration.
Keep `Podfile.lock` in Git and use `pod install` to preserve dependency versions.

Build either configuration from the repository root:

```sh
xcodebuild -workspace VimdowManager.xcworkspace -scheme VimdowManager \
  -configuration Debug -derivedDataPath DerivedData build
xcodebuild -workspace VimdowManager.xcworkspace -scheme VimdowManager \
  -configuration Release -derivedDataPath DerivedData build
```

Both configurations use ad-hoc signing by default, without a development team.
For a build signed with your installed development certificate, pass your own
team ID as a command-line setting:

```sh
xcodebuild -workspace VimdowManager.xcworkspace -scheme VimdowManager \
  -configuration Debug -derivedDataPath DerivedData \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY="Apple Development" build
```

Personal signing settings belong in the build command, not in `project.yml`.

# Modes 

## Command mode (Control-Shift-A)
 - hjkl: Move current window's position 
 - `<shift>`-hjkl: Resize current window based on upper-left
 - `<option>`-hjkl: Resize current window based on bottom-right
 - q + [1-9]: Switch window by displaying shortcut numbers order by x coordinates
    * If you have opened windows more than 9, then simply press 'q' again
 - /: Switch windows by searching app name (e.g. Finder, Chrome, Terminal)
    * n: switch in search result forward
    * N: switch in search result backward
 - x: Quit Vimdow
 - `<escape>`: Exit command mode

## Normal mode 
 - `<option>`-a: Enter command mode
 - `<control>`-`<shift>`-hj: Change window focus to the left
 - `<control>`-`<shift>`-kl: Change window focus to the right

# Notes
- Try to [0-9]+j or [0-9]+h if you want wide step. 

# Roadmap 
- Preferences

# Credits 
- [MASShortcut](https://github.com/shpakovski/MASShortcut)

# Copyright 
- Vimdow is licensed under BSD license.
