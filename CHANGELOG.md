# Changelog

## Unreleased

### Changed

- Cycle marked windows backward with Control–Option–[ and forward with
  Control–Option–], wrapping at both ends of registration order. Each shortcut
  can be changed or cleared independently in Settings.
- Migrate the former Control–Option–Tab default to Control–Option–] once,
  preserving custom shortcuts and cleared bindings.

## [1.1.0](https://github.com/rath/Vimdow/releases/tag/v1.1.0) — 2026-10-03

### Added

- Mark or unmark the focused window with M in command mode. Control–Option–Tab
  cycles only marked windows, in registration order, without moving the pointer.
  The switching shortcut is configurable in Settings.
- Session marks survive minimizing, hiding, and moving windows to another Space.
  Only currently visible windows participate, and closed windows are pruned.
- Brief Marked/Unmarked notices and destination feedback: two 0.18-second pulses
  on a marked switch. Reduce Motion uses one gentle outline fade without tint.
- Homebrew installation through `brew install rath/tap/vimdow`.

### Changed

- Numbered selection now uses 160 × 160-point translucent black badges with large
  white numbers at window centers. Overlapping badges spread into a readable grid.
- Numbered selection cancels after three seconds without keyboard input and
  releases modal shortcuts. Input restarts the timeout while selection is active;
  selecting a window or leaving the mode cancels the timer.
- Updated the four-language website, README demo, and manual testing checklist
  for marked switching, numbered selection, and Homebrew installation.

## [1.0.1](https://github.com/rath/Vimdow/releases/tag/v1.0.1) — 2026-09-29

### Fixed

- Moving and resizing Chrome windows no longer stalls or competes with macOS
  window animations when enhanced Accessibility mode is enabled.

## [1.0.0](https://github.com/rath/Vimdow/releases/tag/v1.0.0) — 2026-09-27

### Added

- First signed and notarized universal binary release of the Swift 6 rewrite.
- Vim-style movement, resizing, counts, snaps, tiling, and per-window undo/redo.
- Numbered window selection, application-name search, and display movement with
  remembered frames.
- Settings for movement and resize steps, animation, display behavior, and
  customizable global shortcuts.
