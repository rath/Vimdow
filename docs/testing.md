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
  Each number is large, white, and centered in a 160-point translucent black
  badge. Check bright/dark windows, small windows, mixed display scales, and
  displays above/left of primary. Overlapping badges form a readable grid near
  their windows' centers, including nine windows sharing a center and windows
  partly off screen. Isolated badges stay centered; all badges stay on their
  assigned display when there is room. Q replaces the previous page; selection
  and Escape remove every badge without the overlays taking focus or clicks.
  With no keyboard input for three seconds, every badge disappears and normal
  typing resumes. Q, an unavailable digit, or an unbound key restarts the idle
  timeout while selection remains active. Select, cancel and re-enter, or open
  search/Settings before the timeout; the old timer must not cancel the new mode.
- [ ] **Search:** `/` stays open and accepts English and Korean composition.
  Enter submits after composition; Escape cancels composition before cancelling
  search. Check focus restoration, no matches, and N/Shift–N navigation.
- [ ] **Marked windows:** with Ghostty, two Chrome windows, and another app open,
  enter command mode then M in Ghostty and one Chrome window. Each shows Marked
  briefly without taking focus and returns to normal typing. Control–Option–Tab
  alternates only those two, leaves the pointer in place, and fires once when
  held. From an unmarked window it selects the first mark. Add a third mark and
  verify registration order, wraparound, and unmark/re-mark appending to the end.
  Ordinary Control–Shift focus shortcuts still include all windows.
- [ ] **Marked focus flash:** each successful marked switch briefly outlines
  and tints only the destination window, pulsing twice over 0.36 seconds without
  taking focus or blocking clicks. Rapid switching replaces the previous pulse.
  Check light/dark mode, full-screen windows, and displays above/left of primary.
  Reduce Motion uses one gentle outline fade without tint. A failed switch or already-focused single mark
  has no flash; ordinary full-window switching has no flash.
- [ ] **Mark lifetime:** minimize a marked window, hide its app, or move it to
  another Space; it is skipped and rejoins on return, even after using Q or search.
  Marks on another visible display participate. Closing a window or quitting its
  app removes that mark on the next operation; reopening does not recreate it.
  One visible mark is a no-op when already focused; zero marks and all-hidden
  marks show distinct notices. Restarting Vimdow clears all marks. Unmarking a
  visible window preserves its undo and display history.
- [ ] **Mark input and feedback:** M uses the physical key with Korean input
  active. Marked switching exits command mode and Q selection, ignores counts,
  and is suspended in search and Settings. Changing or clearing its shortcut
  persists across restart. Rapid mark changes replace the notice and reset its
  0.8-second timer; notices remain readable in light/dark mode and at display
  edges, never intercept typing or clicks, and are announced by VoiceOver.
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
