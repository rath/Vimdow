# Changelog

## [1.3.0](https://github.com/rath/Vimdow/releases/tag/v1.3.0) — 2026-10-09

### Added

- A launcher for applications and System Settings panes: type a name, pick a
  row with Up/Down or Control–N/P, and press Return. It indexes /Applications,
  the system application folders, ~/Applications, Finder, and every pane System
  Settings exposes. It ships without a shortcut; record one such as Option–Command–Space
  under Settings → Shortcuts after turning off Spotlight's Show Finder search
  window shortcut.
- The launcher remembers which item you chose for a query and ranks it first the
  next time. General's Restore Defaults clears this history.
- Dim other windows: Control–Option–D covers every window except the focused
  one with a translucent black layer on every display, like HazeOver. Set the
  intensity (10–90 %) under Settings → General → Dimming; the state and the
  intensity persist, and General's Restore Defaults turns it off. Vimdow's own
  panels, the menu bar, and the Dock stay bright, and full-screen Spaces are
  never dimmed.

### Changed

- Updated the four-language website, README, and manual testing checklist for
  the launcher and dimming. The website's cheat sheet now shows
  Control–Option–[ and Control–Option–] for marked-window cycling.

## [1.2.0](https://github.com/rath/Vimdow/releases/tag/v1.2.0) — 2026-10-05

### Added

- Optional tmux pane numbers after a marked switch into a supported terminal.
  Enable it under Settings → General → Terminal integration; it is off by default.
  Requires tmux focus reporting and the default socket; ambiguous or unavailable
  connections are skipped without sending keys. Disabling it cancels pending work.

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
