import AppKit
import Testing
import VimdowCore

// Share the serialized suite with search tests: sheets are real windows on the test Mac.
extension SearchPanelTests {
    @Test func dimSheetsCoverEveryDisplayWithoutTakingInput() {
        _ = NSApplication.shared
        let overlay = DimOverlay()
        overlay.intensity = 35
        overlay.show(animated: false)
        defer { overlay.hide(animated: false) }
        #expect(overlay.isShowing)
        #expect(overlay.windows.count == NSScreen.screens.count)
        for (window, screen) in zip(overlay.windows, NSScreen.screens) {
            #expect(window.level == .normal)
            #expect(window.ignoresMouseEvents)
            #expect(!window.hasShadow)
            #expect(!window.isOpaque)
            #expect(window.backgroundColor == .black)
            #expect(window.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .stationary, .ignoresCycle]))
            #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
            #expect(!window.canBecomeKey)
            #expect(!window.canBecomeMain)
            #expect(window.isExcludedFromWindowsMenu)
            #expect(window.frame == screen.frame)
            #expect(abs(window.alphaValue - 0.35) < 0.001)
            #expect((window.value(forKey: "_canBeSnappingTarget") as? Bool) == false)
        }
        overlay.intensity = 60
        #expect(overlay.windows.allSatisfy { abs($0.alphaValue - 0.6) < 0.001 })
        overlay.place(.none, ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { $0.isVisible })
        overlay.place(.unavailable, ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        overlay.place(.none, ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { $0.isVisible })
        overlay.hide(animated: false)
        #expect(!overlay.isShowing)
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        overlay.place(.none, ownWindowNumber: nil) // Hidden sheets stay hidden.
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        overlay.show(animated: false)
        #expect(overlay.windows.allSatisfy { abs($0.alphaValue - 0.6) < 0.001 })
    }

    @Test func focusResolutionPicksTheFocusedAppsTopmostMatchingWindow() {
        func entry(_ id: Int, pid: Int32, layer: Int = 0, alpha: Double = 1, _ frame: CGRect) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
             kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: ["X": frame.minX, "Y": frame.minY, "Width": frame.width, "Height": frame.height]]
        }
        let a = CGRect(x: 0, y: 0, width: 400, height: 300)
        let b = CGRect(x: 500, y: 40, width: 640, height: 480)
        let windows = FocusResolution.screenWindows([
            entry(1, pid: 7, a), entry(2, pid: 7, a), entry(3, pid: 7, b),
            entry(4, pid: 7, layer: 25, b), entry(5, pid: 7, alpha: 0, b), entry(6, pid: 8, b),
            [kCGWindowNumber as String: 9], // Unreadable entries are skipped, not fatal.
        ])
        #expect(windows.count == 6)
        #expect(windows[0] == ScreenWindow(id: 1, pid: 7, layer: 0, alpha: 1, bounds: a))
        // Equal bounds resolve to the frontmost entry.
        #expect(FocusResolution.windowID(for: 7, frame: a, in: windows) == 1)
        #expect(FocusResolution.windowID(for: 7, frame: b.offsetBy(dx: 1.5, dy: -1.5), in: windows) == 3)
        // Too far off: fall back to the app's topmost normal-level window.
        #expect(FocusResolution.windowID(for: 7, frame: b.offsetBy(dx: 3, dy: 0), in: windows) == 1)
        #expect(FocusResolution.windowID(for: 8, frame: b, in: windows) == 6)
        #expect(FocusResolution.windowID(for: 9, frame: b, in: windows) == nil)
        let above = FocusResolution.screenWindows([
            entry(11, pid: 1, a), entry(12, pid: 7, a), entry(13, pid: 8, layer: 25, a),
            entry(14, pid: 8, alpha: 0, a), entry(15, pid: 8, a), entry(16, pid: 9, a),
        ])
        #expect(FocusResolution.blockingWindow(in: above, focusedPID: 7, ownPID: 1) == 15)
        #expect(FocusResolution.blockingWindow(in: Array(above.prefix(4)), focusedPID: 7, ownPID: 1) == nil)
        #expect(FocusResolution.matches(a, a.offsetBy(dx: 1.9, dy: 0)))
        #expect(!FocusResolution.matches(a, a.insetBy(dx: 0, dy: 1)))
    }
}
