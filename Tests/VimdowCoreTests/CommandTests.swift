import Foundation
import CoreGraphics
import Testing
@testable import VimdowCore

@Test func repeatPrefixIsConsumedAndCannotOverflow() {
    var prefix = RepeatPrefix()
    prefix.append(1)
    prefix.append(2)
    #expect(prefix.take() == 12)
    #expect(prefix.take() == 1)
    prefix.append(0)
    #expect(prefix.take() == 1)
    for _ in 0..<100 { prefix.append(9) }
    #expect(prefix.take() > 0)
}

@Test func movementAndResizePreserveTheirAnchors() {
    let frame = CGRect(x: -500, y: 100, width: 400, height: 300)
    #expect(WindowGeometry.apply(.down, to: frame, count: 12) == frame.offsetBy(dx: 0, dy: 240))
    let topLeft = WindowGeometry.apply(.left, to: frame, count: 2, anchor: .topLeft)
    #expect(topLeft.origin == frame.origin)
    #expect(topLeft.width == 360)
    let bottomRight = WindowGeometry.apply(.left, to: frame, count: 2, anchor: .bottomRight)
    #expect(bottomRight.maxX == frame.maxX)
    #expect(bottomRight.maxY == frame.maxY)
    #expect(bottomRight.width == 440)
    let clamped = WindowGeometry.apply(.right, to: frame, count: 100, anchor: .bottomRight)
    #expect(clamped.width == 1)
    #expect(clamped.maxX == frame.maxX)
}

@Test func screensUseQuartzCoordinatesIncludingNegativeOrigins() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let left = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
    #expect(WindowGeometry.screenIndex(for: CGRect(x: -1000, y: 0, width: 200, height: 200),
                                       screens: [primary, left]) == 1)
    #expect(WindowGeometry.screenIndex(for: primary, screens: [primary, left]) == 0)
    #expect(WindowGeometry.screenIndex(for: primary, screens: []) == nil)
    #expect(WindowGeometry.screenIndex(for: CGRect(x: -20, y: 100, width: 600, height: 300),
                                       screens: [primary, left]) == 0)
    #expect(WindowGeometry.screenIndex(for: CGRect(x: -2200, y: 0, width: 200, height: 200),
                                       screens: [primary, left]) == 1)
    #expect(WindowGeometry.appKitFrame(from: left, primaryHeight: 900) == CGRect(x: -1920, y: 0, width: 1920, height: 1080))
}

@Test func selectionUsesIdentityAndWrapsSearch() {
    let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    let list = ["Terminal", "Finder", "Terminal"].map { WindowInfo(id: UUID(), name: $0, frame: frame) }
    #expect(WindowSelection.index(in: [], current: nil, step: 1) == nil)
    #expect(WindowSelection.index(in: list, current: list[1].id, step: -1, count: Int.max) == 0)
    #expect(WindowSelection.index(in: list, current: list[1].id, step: 1, count: Int.max) == 2)
    #expect(WindowSelection.index(in: list, current: list[0].id, step: 1, query: "terminal") == 2)
    #expect(WindowSelection.index(in: list, current: list[0].id, step: -1, query: "TERM") == 2)
    #expect(WindowSelection.index(in: list, current: list[0].id, step: 1, count: 2, query: "Terminal") == 0)
    #expect(WindowSelection.index(in: list, current: nil, step: 1, query: "missing") == nil)
}

@Test @MainActor func displayRoundTripRestoresEachDisplaysLatestFrame() {
    let windows = FakeWindows()
    windows.screens.append(CGRect(x: -1440, y: -300, width: 1440, height: 900))
    let original = windows.list[0]
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[1])
    let edited = CGRect(x: -1300, y: -200, width: 900, height: 600)
    windows.list[0] = WindowInfo(id: original.id, name: original.name, frame: edited)
    controller.handle(.escape)
    controller.handle(.enter)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == original.frame)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == edited)
    #expect(ui.errors.isEmpty)
}

@Test @MainActor func displayHistoryIsIndependentForEachWindowAndCyclesThreeDisplays() {
    let windows = FakeWindows()
    windows.screens += [CGRect(x: -1440, y: 0, width: 1440, height: 900),
                        CGRect(x: 0, y: -1200, width: 1920, height: 1200)]
    let originals = Array(windows.list.prefix(2))
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    controller.handle(.enter)
    controller.handle(.nextScreen)
    windows.list.swapAt(0, 1)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[1])
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[2])
    controller.handle(.nextScreen)
    #expect(windows.frames.last == originals[1].frame)
    windows.list.swapAt(0, 1)
    controller.handle(.nextScreen)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == originals[0].frame)
}

@Test @MainActor func displayChangesClearHistoryAndSingleDisplayDoesNotResize() {
    let windows = FakeWindows()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    controller.handle(.enter)
    controller.handle(.nextScreen)
    #expect(windows.frames.isEmpty)
    windows.screens.append(CGRect(x: 1920, y: 0, width: 1440, height: 900))
    controller.handle(.nextScreen)
    windows.screens[0].size.height = 1200
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[0])
    windows.screens = []
    let count = windows.frames.count
    controller.handle(.nextScreen)
    #expect(windows.frames.count == count)
}

@Test @MainActor func failedDisplayMoveDoesNotSaveAnUnvisitedFrame() {
    let windows = FakeWindows()
    windows.screens.append(CGRect(x: 1920, y: 0, width: 1440, height: 900))
    let original = windows.list[0]
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    windows.frameFailure = .unsupportedOperation
    controller.handle(.nextScreen)
    #expect(windows.frames.isEmpty)
    #expect(ui.errors.last as? WindowFailure == .unsupportedOperation)
    windows.frameFailure = nil
    // A manual move after the failed command must not restore a phantom visit.
    windows.list[0] = WindowInfo(id: original.id, name: original.name, frame: windows.screens[1])
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[0])
}

@MainActor
private final class FakeWindows: WindowControlling {
    var list = (0..<12).map { index in
        WindowInfo(id: UUID(), name: index.isMultiple(of: 2) ? "Terminal" : "Finder",
                   frame: CGRect(x: index * 100, y: 100, width: 400, height: 300), isFocused: index == 0)
    }
    var failure: WindowFailure?
    var focused: [UUID] = []
    var frames: [CGRect] = []
    var pointerMoves = 0
    var screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    var frameFailure: WindowFailure?

    func check() throws { if let failure { throw failure } }
    func windows() throws -> [WindowInfo] { try check(); return list }
    func focusedWindow() throws -> WindowInfo {
        try check()
        guard let window = list.first else { throw WindowFailure.noFocusedWindow }
        return window
    }
    func focus(_ id: UUID, movePointer: Bool) throws {
        try check()
        guard list.contains(where: { $0.id == id }) else { throw WindowFailure.unavailableWindow }
        focused.append(id)
        if movePointer { pointerMoves += 1 }
    }
    func setFrame(_ frame: CGRect, of id: UUID) throws {
        try check()
        if let frameFailure { throw frameFailure }
        frames.append(frame)
        if let index = list.firstIndex(where: { $0.id == id }) {
            let window = list[index]
            list[index] = WindowInfo(id: id, name: window.name, frame: frame, isFocused: window.isFocused)
        }
    }
    func screenFrames() -> [CGRect] { screens }
}

@MainActor
private final class FakePresentation: CommandPresenting {
    var modes: [Mode] = []
    var guides: [WindowInfo] = []
    var searchVisible = false
    var errors: [any Error] = []
    var didQuit = false
    func setMode(_ mode: Mode) { modes.append(mode) }
    func showGuides(_ windows: [WindowInfo]) { guides = windows }
    func hideGuides() { guides = [] }
    func showSearch() { searchVisible = true }
    func hideSearch() { searchVisible = false }
    func showFailure(_ error: any Error) { errors.append(error) }
    func quit() { didQuit = true }
}

@Test @MainActor func modesDoNotDuplicateEntryAndReleaseModalInput() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.move(.left))
    #expect(windows.frames.isEmpty)
    controller.handle(.enter)
    controller.handle(.digit(1))
    controller.handle(.enter)
    controller.handle(.digit(2))
    controller.handle(.move(.right))
    #expect(windows.frames.first?.minX == 240)
    #expect(ui.modes == [.command])
    controller.handle(.escape)
    controller.handle(.move(.right))
    #expect(windows.frames.count == 1)
    #expect(controller.mode == .normal)
}

@Test @MainActor func quickSwitchSelectsTheLastPartialPageAndWraps() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.quickSwitch)
    #expect(ui.guides.count == 9)
    controller.handle(.quickSwitch)
    #expect(ui.guides.map(\.id) == windows.list.suffix(3).map(\.id))
    controller.handle(.digit(0))
    controller.handle(.digit(9))
    #expect(windows.focused.isEmpty)
    controller.handle(.digit(3))
    #expect(windows.focused == [windows.list[11].id])
    #expect(windows.pointerMoves == 1)
    #expect(controller.mode == .normal)
    #expect(ui.guides.isEmpty)
    controller.handle(.enter)
    for _ in 0..<3 { controller.handle(.quickSwitch) }
    #expect(ui.guides.first?.id == windows.list[0].id)
}

@Test @MainActor func emptyAndDisappearingWindowsAreSafe() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    windows.list = []
    controller.handle(.cycle(1))
    controller.handle(.enter)
    controller.handle(.quickSwitch)
    controller.handle(.digit(1))
    controller.handle(.move(.left))
    #expect(ui.errors.last as? WindowFailure == .noFocusedWindow)
    #expect(windows.focused.isEmpty)
}

@Test @MainActor func searchCancelRestoresFocusAndRepeatedQueriesStillExecute() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.search)
    #expect(ui.searchVisible)
    controller.handle(.cycle(1))
    #expect(windows.focused.isEmpty)
    controller.finishSearch(nil)
    #expect(windows.focused == [windows.list[0].id])
    #expect(!ui.searchVisible)
    for _ in 0..<2 {
        controller.handle(.search)
        controller.finishSearch("terminal")
    }
    #expect(windows.focused.filter { $0 == windows.list[2].id }.count == 2)
    controller.handle(.repeatSearch(-1))
    #expect(windows.focused.last == windows.list[10].id)
}

@Test(arguments: [WindowFailure.permissionDenied, .unavailableWindow, .unsupportedOperation, .accessibility(-25204)])
@MainActor func failuresDoNotLeaveStaleGuides(_ failure: WindowFailure) {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.quickSwitch)
    windows.failure = failure
    controller.handle(.digit(1))
    #expect(ui.guides.isEmpty)
    #expect(controller.mode == .normal)
    #expect(ui.errors.last as? WindowFailure == failure)
}

@Test @MainActor func scanFailureClearsTheNumberSelectionState() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.quickSwitch)
    windows.failure = .accessibility(-25204)
    controller.handle(.quickSwitch)
    #expect(controller.mode == .command)
    #expect(ui.guides.isEmpty)
    controller.handle(.digit(1))
    #expect(windows.focused.isEmpty)
}

@Test @MainActor func noSearchMatchRestoresTheOriginalApplication() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.search)
    controller.finishSearch("application that is not running")
    #expect(windows.focused == [windows.list[0].id])
    #expect(controller.mode == .command)
    #expect(!ui.searchVisible)
}
