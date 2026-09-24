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
  Escape or period returns ordinary typing to the focused app.
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
