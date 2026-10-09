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
- [ ] **Launcher:** with clean preferences the Open launcher recorder is empty
  and nothing opens a launcher. Recording Option–Command–Space is refused while
  Spotlight's Show Finder search window shortcut is on and accepted after
  turning it off; quit Alfred or clear its hotkey first. The panel opens from
  normal and command mode on the display under the pointer, including over a
  full-screen app, and the same shortcut closes it. `gc`, `sysset`, `wifi`, and
  `battery` show Google Chrome, System Settings, Wi‑Fi, and Battery first.
  Return launches a stopped app, brings a running or hidden app forward, and
  opens a pane in System Settings (try Wi‑Fi, Battery, and General). Korean
  composition filters live while Return and Escape stay in the input method,
  and Return after composition opens the row. Up/Down, Control–N/P, and clicks
  select rows; Escape and clicking another window cancel. Choosing Slack for
  `s` ranks it first on the next open; General's Restore Defaults forgets that
  while Shortcuts' Restore Defaults clears the shortcut. Without Accessibility
  permission the launcher still works and shows no permission alert.
- [ ] **Dim other windows:** with clean preferences the General → Dimming
  checkbox is off and nothing is dimmed. Control–Option–D fades a black layer
  over every window except the focused one on every display within 0.15 s, and
  again fades it out; Reduce Motion makes both instant. Click a dimmed window,
  Cmd-Tab between apps (including to an app whose window sits behind others),
  Cmd-` within one app, minimize and close the focused window, hide and quit the
  frontmost app, and click the desktop: the bright spot follows the focus at
  once, and the desktop click dims everything. Vimdow's own flows stay bright
  and clickable: Control–Shift–H/J/K/L, marked switches and their flash, Q
  badges, search, the launcher, and the Settings window. Dragging a window still
  snaps to a neighbouring window's edge. In Settings, the intensity slider
  previews live and persists; Restore Defaults turns dimming off and resets
  50 %; a shortcut toggle while Settings is open but not key shows when it
  becomes key. Relaunching with dimming on restores it at launch. With two
  displays both dim; a full-screen app leaves its Space untouched while the
  other display still dims, and leaving full screen re-dims. Mission Control
  shows no stray sheets. Revoking Accessibility hides the layer and the shortcut
  shows the permission alert; granting it again and switching apps brings the
  layer back. Vimdow idles near 0 % CPU with dimming on.
- [ ] **Marked windows:** with Ghostty, two Chrome windows, and another app open,
  enter command mode then M in Ghostty and one Chrome window. Each shows Marked
  briefly without taking focus and returns to normal typing. Control–Option–[
  and Control–Option–] alternate only those two, leave the pointer in place,
  and fire once when held. From an unmarked window, ] selects the first mark
  and [ selects the last. Add a third mark and verify forward and backward
  registration order, wraparound at both ends, changing direction, and
  unmark/re-mark appending to the end. Confirm [ and ] also work with Korean input.
  Ordinary Control–Shift focus shortcuts still include all windows.
- [ ] **Marked focus flash:** each successful marked switch briefly outlines
  and tints only the destination window, pulsing twice over 0.36 seconds without
  taking focus or blocking clicks. Rapid switching replaces the previous pulse.
  Check light/dark mode, full-screen windows, and displays above/left of primary.
  Reduce Motion uses one gentle outline fade without tint. A failed switch or already-focused single mark
  has no flash; ordinary full-window switching has no flash.
- [ ] **tmux opt-in:** with clean preferences, pane numbers stay off and the
  General → Terminal integration checkbox is unchecked. Enable it, restart,
  and confirm the choice persists. Disable during a pending switch; no delayed
  pane display should appear. General's Restore Defaults turns it off, while
  Shortcuts' Restore Defaults leaves it unchanged.
- [ ] **tmux after marked switching:** enable the Terminal integration checkbox
  and `set -s focus-events on` in a local default-socket tmux, then reattach.
  Mark Ghostty or Alacritty and another
  app; switching back with either marked shortcut should show pane numbers and
  allow numeric selection. Try multiple terminal windows/tabs and rapid switches;
  only the focused client's panes should be shown. Leaving the target during
  lookup cancels the action. Ordinary app switching, whole-window cycling,
  failed switches, and an already-focused single mark must not trigger it.
  Plain shells, no server, focus reporting off, SSH-only tmux, custom sockets,
  and ambiguous clients must stay untouched. Check Terminal only if that version
  supports focus reporting; otherwise it should be skipped. Test both stable
  tmux (client targets) and newer pane-targeting versions.
- [ ] **Mark lifetime:** minimize a marked window, hide its app, or move it to
  another Space; it is skipped and rejoins on return, even after using Q or search.
  Marks on another visible display participate. Closing a window or quitting its
  app removes that mark on the next operation; reopening does not recreate it.
  One visible mark is a no-op when already focused; zero marks and all-hidden
  marks show distinct notices. Restarting Vimdow clears all marks. Unmarking a
  visible window preserves its undo and display history.
- [ ] **Mark input and feedback:** M uses the physical key with Korean input
  active. Marked switching exits command mode and Q selection, ignores counts,
  and is suspended in search and Settings. Settings shows separate Previous
  marked window and Next marked window recorders. Changing or clearing either
  persists across restart; Restore Defaults returns them to [ and ]. Upgrade
  an old Tab default and confirm it becomes ]; custom and cleared bindings stay
  intact. Explicitly reassign Tab afterward and confirm it survives restart.
  Rapid mark changes replace the notice and reset its
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
