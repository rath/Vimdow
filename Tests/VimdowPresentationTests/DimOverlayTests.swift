import AppKit
import ApplicationServices
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
        overlay.place(FocusUpdate(target: .none), ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { $0.isVisible })
        overlay.place(FocusUpdate(target: .unavailable), ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        overlay.place(FocusUpdate(target: .none), ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { $0.isVisible })
        overlay.hide(animated: false)
        #expect(!overlay.isShowing)
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        overlay.place(FocusUpdate(target: .none), ownWindowNumber: nil) // Hidden sheets stay hidden.
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
        let focused = ScreenWindow(id: 17, pid: 7, layer: 0, alpha: 1, bounds: a)
        #expect(FocusResolution.blockingWindow(above: 17, in: above + [focused], focusedPID: 7, ownPID: 1) == 15)
        #expect(FocusResolution.blockingWindow(above: 17, in: Array(above.prefix(4)) + [focused] + Array(above.suffix(2)),
                                               focusedPID: 7, ownPID: 1) == nil)
        #expect(FocusResolution.blockingWindow(above: 99, in: above, focusedPID: 7, ownPID: 1) == nil)
        #expect(FocusResolution.matches(a, a.offsetBy(dx: 1.9, dy: 0)))
        #expect(!FocusResolution.matches(a, a.insetBy(dx: 0, dy: 1)))
    }

    @Test func focusReadsOneWindowListAndBatchesWindowAttributes() {
        let probe = FocusReadProbe()
        let (update, window) = probe.reader.resolve(ownPID: 1, reasons: .application)
        #expect(update.target == .window(id: 10, pid: 7, frame: probe.frame, isFullScreen: false))
        #expect(window != nil)
        #expect(update.windows == probe.snapshot)
        #expect(update.reasons == .application)
        #expect(probe.singleReads == [kAXFocusedWindowAttribute])
        #expect(probe.batchReads == 1)
        #expect(probe.windowReads == 1)
        #expect(FocusResolution.blockingWindow(above: 10, in: update.windows, focusedPID: 7, ownPID: 1) == 20)
    }

    @Test func focusBatchHandlesOptionalErrorsAndRejectsMissingGeometry() {
        let probe = FocusReadProbe()
        var error = AXError.attributeUnsupported
        let unsupported = AXValueCreate(.axError, &error)!
        probe.values[0] = unsupported
        probe.values[3] = kCFNull!
        #expect(probe.reader.resolve(ownPID: 1, reasons: []).0.target ==
                .window(id: 10, pid: 7, frame: probe.frame, isFullScreen: false))
        probe.values[3] = true
        #expect(probe.reader.resolve(ownPID: 1, reasons: []).0.target ==
                .window(id: 10, pid: 7, frame: probe.frame, isFullScreen: true))
        for invalid in [unsupported as Any, kCFNull as Any, "invalid" as Any, probe.values[2]] {
            probe.values[1] = invalid
            #expect(probe.reader.resolve(ownPID: 1, reasons: []).0.target == .none)
        }
        #expect(probe.windowReads == 2)
        #expect(probe.singleReads.allSatisfy { $0 == kAXFocusedWindowAttribute })
    }

    @Test func focusBatchFallsBackOnlyWhenUnimplemented() {
        let fallback = FocusReadProbe()
        fallback.status = .notImplemented
        #expect(fallback.reader.resolve(ownPID: 1, reasons: []).0.target ==
                .window(id: 10, pid: 7, frame: fallback.frame, isFullScreen: false))
        #expect(fallback.singleReads == [kAXFocusedWindowAttribute, kAXMinimizedAttribute,
                                         kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"])
        #expect(fallback.batchReads == 1)
        #expect(fallback.windowReads == 1)
        for error in [AXError.cannotComplete, .invalidUIElement, .apiDisabled, .failure] {
            let probe = FocusReadProbe()
            probe.status = error
            #expect(probe.reader.resolve(ownPID: 1, reasons: []).0.target == .none)
            #expect(probe.singleReads == [kAXFocusedWindowAttribute])
            #expect(probe.batchReads == 1)
            #expect(probe.windowReads == 0)
        }
        let malformed = FocusReadProbe()
        malformed.values = []
        #expect(malformed.reader.resolve(ownPID: 1, reasons: []).0.target == .none)
        #expect(malformed.windowReads == 0)
        let minimized = FocusReadProbe()
        minimized.values[0] = true
        #expect(minimized.reader.resolve(ownPID: 1, reasons: []).0.target == .none)
        #expect(minimized.windowReads == 0)
    }

    @Test func focusShortCircuitsWithoutExternalFocusedWindow() {
        let probe = FocusReadProbe()
        var reader = probe.reader
        reader.isTrusted = { false }
        #expect(reader.resolve(ownPID: 1, reasons: []).0.target == .unavailable)
        reader.isTrusted = { true }
        reader.frontmostPID = { nil }
        #expect(reader.resolve(ownPID: 1, reasons: []).0.target == .none)
        reader.frontmostPID = { 1 }
        #expect(reader.resolve(ownPID: 1, reasons: []).0.target == .ownApp)
        #expect(probe.singleReads.isEmpty)
        #expect(probe.batchReads == 0)
        #expect(probe.windowReads == 0)
    }

    @Test func sheetOrderingRequiresAllSheetsBesideTheAnchor() {
        func window(_ id: CGWindowID, layer: Int = 0, alpha: Double = 1) -> ScreenWindow {
            ScreenWindow(id: id, pid: 7, layer: layer, alpha: alpha, bounds: .zero)
        }
        let sheets: Set<CGWindowID> = [2, 3]
        let ordered = [window(1), window(8, layer: 25), window(9, alpha: 0), window(3), window(2), window(4)]
        #expect(FocusResolution.sheetsAreOrdered(sheets, beside: 1, above: false, in: ordered))
        #expect(FocusResolution.sheetsAreOrdered(sheets, beside: 4, above: true, in: ordered))
        #expect(!FocusResolution.sheetsAreOrdered(sheets, beside: 1, above: true, in: ordered))
        #expect(!FocusResolution.sheetsAreOrdered(sheets, beside: 4, above: false, in: ordered))
        #expect(!FocusResolution.sheetsAreOrdered(sheets, beside: 99, above: false, in: ordered))
        #expect(!FocusResolution.sheetsAreOrdered(sheets, beside: 1, above: false,
                                                 in: [window(1), window(2), window(4), window(3)]))
        #expect(!FocusResolution.sheetsAreOrdered(sheets, beside: 1, above: false, in: [window(1), window(2)]))
        // Sheets remain relevant during their fade through alpha zero.
        #expect(FocusResolution.sheetsAreOrdered(sheets, beside: 1, above: false,
                                                in: [window(1), window(2, alpha: 0), window(3)]))
    }

    @Test func focusRefreshMergesCausesAndDiscardsWorkFromPreviousRun() async throws {
        var reader = FocusReader()
        reader.frontmostPID = { nil } // No live AX observer in this test.
        var resolutions = 0
        reader.isTrusted = { resolutions += 1; return true }
        let tracker = FocusTracker(reader: reader)
        var updates: [FocusUpdate] = []
        tracker.onUpdate = { updates.append($0) }
        tracker.start()
        defer { tracker.stop() }
        tracker.refresh()
        tracker.refresh(reason: .application)
        tracker.refresh(reason: .space)
        tracker.refresh(reason: .screens)
        try await awaitDimCondition { updates.count == 2 }
        #expect(resolutions == 2) // One initial resolve and one merged refresh.
        #expect(updates[1].reasons == [.accessibility, .application, .space, .screens])
        tracker.refresh(reason: .space)
        tracker.stop()
        tracker.start()
        tracker.refresh()
        try await awaitDimCondition { updates.count == 4 }
        #expect(resolutions == 4)
        #expect(updates[2].reasons == .initial)
        #expect(updates[3].reasons == .accessibility)
    }

    @Test func duplicatePlacementPreservesSettleAndRepairsIncorrectOrder() async throws {
        let probe = DimPlacementProbe()
        let overlay = probe.makeOverlay()
        overlay.show(animated: false)
        defer { overlay.hide(animated: false); probe.finishAll() }
        try #require(!overlay.windows.isEmpty)
        let count = overlay.windows.count
        let update = probe.update(for: overlay, id: 10)
        overlay.place(update, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 1 }
        for _ in 0..<5 { overlay.place(update, ownWindowNumber: nil) }
        #expect(probe.orders.count == count)
        #expect(probe.waiters.count == 1)
        probe.finish(0)
        try await awaitDimCondition { probe.orders.count == count * 2 }
        overlay.place(update, ownWindowNumber: nil)
        #expect(probe.orders.count == count * 2)
        #expect(probe.waiters.count == 1)

        // Same target, but another window now separates the sheets from it.
        var displaced = update
        displaced.windows.insert(ScreenWindow(id: 30, pid: 8, layer: 0, alpha: 1, bounds: .zero), at: 1)
        overlay.place(displaced, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 2 }
        #expect(probe.orders.count == count * 3)
        overlay.place(update, ownWindowNumber: nil)
        #expect(probe.orders.count == count * 3)
        probe.finish(1)
        try await awaitDimCondition { probe.orders.count == count * 4 }
    }

    @Test func forcedPlacementAndRapidSwitchesInvalidateOldSettle() async throws {
        let probe = DimPlacementProbe()
        let overlay = probe.makeOverlay()
        overlay.show(animated: false)
        defer { overlay.hide(animated: false); probe.finishAll() }
        try #require(!overlay.windows.isEmpty)
        let count = overlay.windows.count
        let a = probe.update(for: overlay, id: 10)
        let b = probe.update(for: overlay, id: 20)
        overlay.place(a, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 1 }
        overlay.place(b, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 2 }
        overlay.place(a, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 3 }
        probe.finishAll()
        try await awaitDimCondition { probe.completedSleeps == 3 }
        #expect(probe.orders.count == count * 4) // Three immediate orders, only the latest settle.
        #expect(probe.orders.suffix(count).allSatisfy { $0.anchor == 10 && $0.mode == .below })

        for reason in [FocusUpdate.Reasons.application, .space, .screens] {
            var forced = a
            forced.reasons = reason
            overlay.place(forced, ownWindowNumber: nil)
        }
        #expect(probe.orders.count == count * 7)
        // A cancelled task may start late; all three still have to be harmless after hide.
        overlay.hide(animated: false)
        try await awaitDimCondition { probe.waiters.count == 6 }
        probe.finishAll()
        try await awaitDimCondition { probe.completedSleeps == 6 }
        #expect(probe.orders.count == count * 7)
    }

    @Test func rebuildingAndTogglingNeverReuseOldPlacement() async throws {
        let probe = DimPlacementProbe()
        let overlay = probe.makeOverlay()
        overlay.show(animated: false)
        defer { overlay.hide(animated: false); probe.finishAll() }
        try #require(!overlay.windows.isEmpty)
        let count = overlay.windows.count
        overlay.place(probe.update(for: overlay, id: 10), ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 1 }
        overlay.rebuildScreens()
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        #expect(probe.orders.count == count)
        var update = probe.update(for: overlay, id: 10)
        update.reasons = .screens
        overlay.place(update, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 2 }
        overlay.hide(animated: false)
        overlay.show(animated: false)
        overlay.place(probe.update(for: overlay, id: 10), ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 3 }
        probe.finishAll()
        try await awaitDimCondition { probe.completedSleeps == 3 }
        #expect(probe.orders.count == count * 4)
    }

    @Test func blockerPlacementUsesSnapshotAndSettlesBelowFocusedWindow() async throws {
        let probe = DimPlacementProbe()
        let overlay = probe.makeOverlay()
        overlay.show(animated: false)
        defer { overlay.hide(animated: false); probe.finishAll() }
        try #require(!overlay.windows.isEmpty)
        let count = overlay.windows.count
        let base = probe.update(for: overlay, id: 10)
        let blocker = ScreenWindow(id: 20, pid: 8, layer: 0, alpha: 1, bounds: .zero)
        var blocked = base
        blocked.windows = [blocker] + base.windows
        overlay.place(blocked, ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 1 }
        #expect(probe.orders.count == count)
        #expect(probe.orders.allSatisfy { $0.mode == .above && $0.anchor == 20 })
        // A duplicate sees the sheets already above the blocker and keeps the same settle.
        blocked.windows = Array(base.windows.dropFirst()) + [blocker, base.windows[0]]
        overlay.place(blocked, ownWindowNumber: nil)
        #expect(probe.orders.count == count)
        probe.finish(0)
        try await awaitDimCondition { probe.orders.count == count * 2 }
        #expect(probe.orders.suffix(count).allSatisfy { $0.mode == .below && $0.anchor == 10 })
    }

    @Test func fullScreenSkipsItsDisplayAndCancelsThePreviousPlacement() async throws {
        let probe = DimPlacementProbe()
        let overlay = probe.makeOverlay()
        overlay.show(animated: false)
        defer { overlay.hide(animated: false); probe.finishAll() }
        let primary = try #require(NSScreen.screens.first)
        let count = overlay.windows.count
        overlay.place(probe.update(for: overlay, id: 10), ownWindowNumber: nil)
        try await awaitDimCondition { probe.waiters.count == 1 }
        var fullscreen = probe.update(for: overlay, id: 10)
        fullscreen = FocusUpdate(target: .window(id: 10, pid: 7,
            frame: WindowGeometry.quartzFrame(from: primary.frame, primaryHeight: primary.frame.height),
            isFullScreen: true), windows: fullscreen.windows, reasons: .space)
        overlay.place(fullscreen, ownWindowNumber: nil)
        #expect(!overlay.windows[0].isVisible)
        #expect(probe.orders.count == count + count - 1)
        let sleeps = count == 1 ? 1 : 2
        try await awaitDimCondition { probe.waiters.count == sleeps }
        probe.finishAll()
        try await awaitDimCondition { probe.completedSleeps == sleeps }
        #expect(!overlay.windows[0].isVisible)
        #expect(probe.orders.count == count + 2 * (count - 1))

        overlay.place(probe.update(for: overlay, id: 10), ownWindowNumber: nil)
        #expect(overlay.windows.allSatisfy { $0.isVisible })
        try await awaitDimCondition { probe.waiters.count == sleeps + 1 }
        overlay.place(FocusUpdate(target: .unavailable), ownWindowNumber: nil)
        probe.finishAll()
        try await awaitDimCondition { probe.completedSleeps == sleeps + 1 }
        #expect(overlay.windows.allSatisfy { !$0.isVisible })
        #expect(probe.orders.count == 2 * count + 2 * (count - 1))
    }
}

@MainActor private final class FocusReadProbe {
    let frame = CGRect(x: 30, y: 40, width: 500, height: 400)
    var values: [Any]
    var status = AXError.success
    var singleReads: [String] = []
    var batchReads = 0
    var windowReads = 0
    var snapshot: [ScreenWindow] {
        [ScreenWindow(id: 20, pid: 8, layer: 0, alpha: 1, bounds: .zero),
         ScreenWindow(id: 10, pid: 7, layer: 0, alpha: 1, bounds: frame)]
    }

    init() {
        var point = frame.origin
        var size = frame.size
        values = [false, AXValueCreate(.cgPoint, &point)!, AXValueCreate(.cgSize, &size)!, false]
    }

    var reader: FocusReader {
        FocusReader(isTrusted: { true }, frontmostPID: { 7 }, attribute: { [self] _, name in
            singleReads.append(name)
            if name == kAXFocusedWindowAttribute { return AXUIElementCreateApplication(7) }
            let names = [kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"]
            guard let index = names.firstIndex(of: name), index < values.count else { return nil }
            return values[index] as CFTypeRef
        }, attributes: { [self] _, names in
            #expect(names == [kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"])
            batchReads += 1
            return (status, values)
        }, windows: { [self] in
            windowReads += 1
            return snapshot
        })
    }
}

/// Sleep deliberately ignores cancellation until resumed, to exercise the generation guards.
@MainActor private final class DimPlacementProbe {
    var waiters: [CheckedContinuation<Void, Never>?] = []
    var completedSleeps = 0
    var orders: [(mode: NSWindow.OrderingMode, anchor: Int)] = []

    func makeOverlay() -> DimOverlay {
        DimOverlay(sleep: { [self] duration in
            #expect(duration == DimOverlay.settleDelay)
            await withCheckedContinuation { waiters.append($0) }
            completedSleeps += 1
        }, order: { [self] window, mode, anchor in
            orders.append((mode, anchor))
            window.orderFrontRegardless() // Synthetic anchor IDs must not reach Window Server.
        })
    }

    func finish(_ index: Int) {
        waiters[index]?.resume()
        waiters[index] = nil
    }

    func finishAll() {
        for index in waiters.indices { finish(index) }
    }

    func update(for overlay: DimOverlay, id: CGWindowID) -> FocusUpdate {
        let frame = CGRect(x: 30, y: 40, width: 500, height: 400)
        let target = FocusTarget.window(id: id, pid: 7, frame: frame, isFullScreen: false)
        let focused = ScreenWindow(id: id, pid: 7, layer: 0, alpha: 1, bounds: frame)
        let sheets = overlay.windows.map {
            ScreenWindow(id: CGWindowID($0.windowNumber), pid: ProcessInfo.processInfo.processIdentifier,
                         layer: 0, alpha: 1, bounds: .zero)
        }
        return FocusUpdate(target: target, windows: [focused] + sheets, reasons: .accessibility)
    }
}

@MainActor private func awaitDimCondition(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition(), "Timed out waiting for dimming work")
}
