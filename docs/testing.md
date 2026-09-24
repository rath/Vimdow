# Manual testing

See [README](../README.md#tests) for automated tests. They do not establish
real Accessibility, keyboard-repeat, Korean IME, or multi-monitor behavior.

Run one installed copy of Vimdow. Use the default shortcuts below, or your
configured equivalents. Enter command mode with Control–Option–A, then release
the keys. Record the macOS version, architecture, display setup, and results
in the relevant PR or issue. Check supported OS versions before a release.

## Checklist

- [ ] **Permissions:** without Accessibility permission, Settings opens and
  window commands offer guidance. Granting permission enables commands;
  revoking it releases modal keys after the next window command.
- [ ] **Movement and resize:** try `hjkl`, held keys, and `12j`. Configured steps
  apply; Option/Shift resize keeps the top-left/bottom-right corner fixed.
  Held Option/Shift resizes stop exactly at the menu bar, the Dock, and each
  display edge, including on a secondary display, and pass them when the edge
  setting is off. Taps glide one step, held keys move and resize smoothly, and
  counts glide the whole distance; every glide ends on the step with fixed
  edges unchanged. Q, focus cycling, and display moves right after a glide land
  on its final frame. With animation off, steps apply at once. Escape or period
  returns ordinary typing to the focused app.
- [ ] **Undo and redo:** after a held key, `12j`, a resize, `zz`, and a display
  move, `u` steps back one change at a time and Control–R steps forward.
  Repeated taps of one key undo at once like a held key, and `3u` undoes three
  changes. Each window keeps its own history, and a new change clears redo.
  Undo glides except across display moves. After dragging a window, undo
  restores the recorded frame and redo returns it to the dragged position.
- [ ] **Snaps and tiling:** `0`, `$`, `gg`, `G`, and `zz` move the window to the
  edges and center of its display without resizing it, clear of the menu bar
  and Dock, including a Dock on the side and a display above or left of the
  primary. Control–W then Shift–H / J / K / L fills the matching half and
  Control–W then O fills the display; the two halves meet without a gap.
  `10j` still moves ten steps, `g` then `j` does nothing, and repeating
  Control–W then Shift–H changes nothing and adds no undo step. `0` during a
  glide lands on the edge, a nonresizable window beeps on Control–W then
  Shift–H, `u` undoes each placement, and `zz` recovers a window dragged mostly
  off screen. Control–W does not close a browser tab while command mode is
  active.
- [ ] **Window selection:** use Q with more than nine windows, page again,
  and select a number. The right window activates and the pointer centers on it.
- [ ] **Search:** `/` stays open and accepts English and Korean composition.
  Enter submits after composition; Escape cancels composition before cancelling
  search. Check focus restoration, no matches, and N/Shift–N navigation.
- [ ] **Displays:** move small-to-large and back, including displays above/left
  of primary. First visits follow Fill Display/Keep Size; return visits restore
  each window's last frame. A single display is unchanged; layout changes clear
  history. Check labels on mixed display scales.
- [ ] **Settings:** comma, the app menu, and reopening Vimdow reuse one window.
  Shortcuts pause while editing and resume in normal mode after leaving it.
  Movement/resize values apply separately; invalid input is not saved.
- [ ] **Shortcut preferences:** edit or clear a global shortcut, restart, and
  confirm persistence. Reopen the app to recover a cleared entry shortcut.
  Detected conflicts are rejected; Restore Defaults resets only its own tab.
- [ ] **App compatibility:** try Finder, Terminal, a browser, nonresizable
  dialogs, Spaces, and full-screen apps. Closing a target or unplugging a display
  must not crash Vimdow or leave stale guides.

Other apps can constrain window size or reject Accessibility operations.
Inspect Console under subsystem `rath.toys.VimdowManager` when diagnosing failures.
