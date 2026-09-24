# Migration validation

The behavior baseline is the Objective-C implementation at `a5cc1b3`.
The Swift migration targets macOS 14+, preserves window-management commands,
and removes F9/F10 audio control and F13 iTunes control.

## Automated checks

Run setup and the Debug/Release build commands in the README. Run the
`VimdowCore` test scheme for pure logic and the `VimdowShortcuts` scheme on an
interactive Mac for real shortcut registration and teardown.

The core suite covers:

- Repeat-prefix consumption and integer overflow.
- Movement and both resize anchors, including minimum positive dimensions.
- Quartz/AppKit coordinates and displays with negative origins.
- Display round trips restore each window's per-display position and size;
  manual adjustments, three-display cycles, failed moves, layout changes, and
  single-display no-ops are covered.
- Empty window lists, window identity, focus boundaries, and case-insensitive
  search with wraparound.
- Idempotent command-mode entry and cleanup on mode exit.
- Numbered selection beyond nine windows, the last partial page, and wrapping.
- Search cancellation, repeated identical queries, and no-result focus restoration.
- Permission denial, vanished windows, unsupported operations, and AX failures.

The shortcut suite briefly registers all actual bindings and verifies that
modifier-free keys are released in normal/search modes and at shutdown.
It does not synthesize keystrokes or control other applications.

The `VimdowPresentation` scheme shows the real AppKit search panel. It verifies
that showing/changing the first responder does not submit a query, that the
panel takes keyboard focus while other apps can remain active, that Return
submits the live field-editor text once, and that marked text keeps Return and
Escape within the input method. Testing with an actual Korean input source
remains part of the manual matrix.

The search regression was reproduced in a standalone AppKit app: assigning the
first responder called `textDidEndEditing`, which submitted an empty query and
immediately hid the panel. Submission now uses explicit Return handling, and
the panel takes keyboard focus without depending on app activation. All three
presentation tests passed after the fix, and a standalone launch confirmed the
panel remained visible and key after showing.

### Recorded migration checks — 2026-09-24

Environment: Apple Silicon, macOS 26.6.2, Xcode 27.0 (27A266a), Swift 6.4,
XcodeGen 2.46.0, KeyboardShortcuts 3.1.0.

- Debug app build and all 11 core tests passed (including four parameterized
  AX failure cases).
- The separate global-shortcut registration/cleanup test passed.
- Release built successfully both in the working tree and in a clean source
  copy with no Pods, generated project, workspace, or build artifacts.
- Setup succeeded from outside the repository. The generated and canonical
  dependency lock files matched byte for byte, including in the clean copy.
- Release contains arm64 and x86_64, declares macOS 14.0 minimum, retains bundle
  ID `rath.toys.VimdowManager`, and has ad-hoc signing with no team identifier.
- The final bundle includes the icon, credits, KeyboardShortcuts resources and
  license notice, and contains no old nib or MASShortcut bundle.

**Not executed:** the manual matrix below, including Accessibility control of
other apps, real held-key behavior, IME interaction, mixed-display setups, and
runtime checks on macOS 14 or 27. Automated registration tests do not establish
those behaviors. Xcode emitted its standard unused-AppIntents metadata warning;
the shortcut test also logged system `linkd` connection diagnostics while passing.

### Display restoration follow-up — 2026-09-24

All 15 core tests and the Release app build passed after adding per-display
frame history. AX frame updates now move before resizing, then reapply the
origin if the target app changed it. This avoids requesting the destination's
size while the window is still on the source display. Live AX behavior across
different display sizes still requires the manual checks below.

### Settings follow-up — 2026-09-24

- All 19 core, 4 shortcut, and 5 presentation tests passed; Debug and universal
  Release builds succeeded.
- A standalone app using the production settings controller confirmed a visible
  key window. Both tabs were visually checked in light and dark appearances at
  the minimum window width. Unhosted XCTest cannot reliably activate a regular
  application window, so key-window activation was verified separately; its
  tests cover live field-editor input, window reuse, and shortcut suspension.
- Tests isolate preferences in temporary suites and use separate shortcut names.
  Actual Korean IME input, other-app conflicts, and live AX display transfers
  with the new options remain manual acceptance checks.

## Manual acceptance matrix

Run these on macOS 14 and the current supported macOS, with Accessibility
permission granted to the exact app bundle being tested. Record the OS and
architecture; a successful cross-compile does not establish runtime support.

| Scenario | Expected result |
| --- | --- |
| First launch without permission | Guidance appears; Later leaves the app running; a window command retries permission while Settings remains available. |
| Grant permission while running | The next window command works without an app restart; Settings refreshes permission status when activated. |
| Revoke permission during command mode | The next command exits the mode and offers guidance; plain keys are released. |
| Enter command mode repeatedly | Each key triggers one action; a numeric prefix survives redundant entry. |
| `hjkl`, `12j`, held movement keys | Correct direction and 20-point units; held keys follow system repeat timing. |
| Option/Shift resize in all directions | Top-left/bottom-right anchors respectively remain fixed, subject to the target app's size constraints. |
| Escape and period | Plain letters and numbers immediately return to the focused app. |
| Q with 0, 1, 9, 10, 12, and 19 windows | At most nine labels; paging wraps; only visible numbers select; the last page selects the correct window. |
| Number selection | The selected window activates and the pointer moves to its center. |
| `/`, Enter, Escape, N, Shift–N | Search by app name, next/previous matching window, cancellation and focus restoration work. |
| Korean IME and English search input | Marked text composition works; Escape first cancels composition; normal copy/paste works. |
| No search match / target closes during search | No crash; restore the previous window if still available. |
| Finder, Terminal, browser; dialogs and nonresizable windows | Supported operations work; unsupported operations fail safely. |
| Two windows with identical positions and dimensions | Focus identity is not inferred from geometry. |
| Mixed Retina/non-Retina displays; display above/left of primary | Labels use the correct coordinates and remain sharp; first visits fill the intended display and return visits restore the previous position and size. Check small-to-large and large-to-small moves. |
| Adjust a window on either display, then cycle displays | Each window restores its most recent frame on each display independently. |
| One display; display layout or resolution changed | One display is a no-op; layout changes clear remembered frames. |
| Spaces, full-screen apps, Stage Manager | Only eligible visible windows are offered; labels do not steal focus. |
| Screen unplugged; target closes between scan and selection | No crash, stale labels are removed. |
| Command mode then comma; app menu Settings; reopen running app | One Settings window opens, including without Accessibility permission. |
| Settings focus, another app, then Settings again | All shortcuts pause while editing; normal global shortcuts resume outside Settings; modal letters never leak into the form. |
| Movement 7pt, resize 31pt, numeric prefixes | Separate values apply immediately; prefixes multiply the configured step. |
| Empty, Korean, fractional, out-of-range step input | Invalid values are not persisted; leaving the field restores its last valid value. |
| Edit/clear global shortcuts and restart | Changes persist; cleared shortcuts do not cause conflict alerts; reopening the app remains a recovery route. |
| Duplicate or system/menu-conflicting shortcut | Recording is rejected with an explanation; the previous assignment survives. |
| Restore Defaults in either tab | Only that tab resets; the other tab is unchanged. |
| Keep Size; smaller/negative-origin displays; return trip | First visit preserves size/offset where possible and fits within the target; return restores the saved frame. |
| F9/F10/F13 | Vimdow no longer registers these keys. |

## Known constraints

- Other apps may reject Accessibility operations or enforce their own minimum
  window size. AX errors are logged under subsystem `rath.toys.VimdowManager`.
- Window discovery combines on-screen Quartz bounds with public AX windows.
  It does not use private window identifiers or require screen capture for previews.
- First visits to a display fill its bounds by default, or keep size/offset when
  selected in Settings. Return visits restore the
  frame saved when that window last left the display. History lasts for the
  running session and is cleared when the display layout changes.
- Ad-hoc development builds may need their Accessibility entry re-added after
  rebuilding or moving the bundle.
- Signed distribution, notarization, login items, and automatic
  updates are outside this migration.
