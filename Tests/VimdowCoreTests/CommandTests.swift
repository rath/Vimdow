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

@Test @MainActor func settingsUseIndependentStepsAndUpdateWithoutRestarting() {
    let windows = FakeWindows()
    var settings = WindowPreferences(moveStep: 7, resizeStep: 3)
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation(), preferences: { settings })
    controller.handle(.enter)
    controller.handle(.digit(2))
    controller.handle(.move(.right))
    #expect(windows.frames.last?.minX == 14)
    controller.handle(.digit(3))
    controller.handle(.resize(.down, .topLeft))
    #expect(windows.frames.last?.height == 309)
    settings = WindowPreferences(moveStep: 50, resizeStep: 10)
    controller.handle(.move(.right))
    #expect(windows.frames.last?.minX == 64)
    #expect(WindowPreferences(moveStep: 0, resizeStep: 201) == WindowPreferences())
}

@Test @MainActor func settingsSuspendCommandsAndClearModalStateWithoutPermission() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    controller.handle(.enter)
    controller.handle(.quickSwitch)
    controller.handle(.settings)
    #expect(controller.mode == .settings)
    #expect(ui.guides.isEmpty)
    windows.failure = .permissionDenied
    controller.handle(.settings)
    controller.handle(.cycle(1))
    controller.handle(.move(.left))
    #expect(ui.errors.isEmpty)
    controller.setSettingsActive(false)
    #expect(controller.mode == .normal)
    windows.failure = nil
    controller.handle(.enter)
    controller.handle(.digit(9))
    controller.handle(.settings)
    controller.setSettingsActive(false)
    controller.handle(.enter)
    controller.handle(.move(.right))
    #expect(windows.frames.last?.minX == 20)
    controller.handle(.search)
    controller.handle(.settings)
    #expect(!ui.searchVisible)
    #expect(controller.mode == .settings)
}

@Test @MainActor func keepSizePreservesOffsetsAndRoundTripsWhileBehaviorChangesResetHistory() {
    let windows = FakeWindows()
    windows.screens.append(CGRect(x: -1440, y: -300, width: 1440, height: 900))
    let original = windows.list[0].frame
    var settings = WindowPreferences(displayBehavior: .keepSize)
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation(), preferences: { settings })
    controller.handle(.enter)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == original.offsetBy(dx: -1440, dy: -300))
    controller.handle(.nextScreen)
    #expect(windows.frames.last == original)
    settings = WindowPreferences(displayBehavior: .fillDisplay)
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[1])
    controller.resetDisplayHistory()
    controller.handle(.nextScreen)
    #expect(windows.frames.last == windows.screens[0])
}

@Test func keepSizeFitsSmallDisplaysAndOffscreenWindows() {
    let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let target = CGRect(x: -800, y: -600, width: 800, height: 600)
    #expect(WindowGeometry.transfer(source, from: source, to: target) == target)
    let partlyOffscreen = CGRect(x: 1700, y: 900, width: 400, height: 300)
    #expect(WindowGeometry.transfer(partlyOffscreen, from: source, to: target)
            == CGRect(x: -400, y: -300, width: 400, height: 300))
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

@Test func growthStopsAtDisplayEdgesWithoutMovingOtherEdges() {
    let display = CGRect(x: -1440, y: -300, width: 1440, height: 875)
    let frame = CGRect(x: -1400, y: -250, width: 400, height: 300)
    func limited(_ direction: Direction, _ anchor: ResizeAnchor, count: Int = 10, from start: CGRect = frame) -> CGRect {
        let resized = WindowGeometry.apply(direction, to: start, count: count, anchor: anchor)
        return WindowGeometry.limitGrowth(from: start, to: resized, within: display)
    }
    #expect(limited(.left, .bottomRight) == CGRect(x: -1440, y: -250, width: 440, height: 300))
    #expect(limited(.up, .bottomRight) == CGRect(x: -1400, y: -300, width: 400, height: 350))
    #expect(limited(.right, .topLeft, count: 100) == CGRect(x: -1400, y: -250, width: 1400, height: 300))
    #expect(limited(.down, .topLeft, count: 100) == CGRect(x: -1400, y: -250, width: 400, height: 825))
    // Growth that stays inside the display and shrinking are unchanged.
    #expect(limited(.left, .bottomRight, count: 1) == CGRect(x: -1420, y: -250, width: 420, height: 300))
    #expect(limited(.left, .topLeft) == WindowGeometry.apply(.left, to: frame, count: 10, anchor: .topLeft))
    // An edge already past the display neither grows further nor snaps back,
    // and shrinking it may cross the display edge.
    let outside = frame.offsetBy(dx: -100, dy: 0)
    #expect(limited(.left, .bottomRight, from: outside) == outside)
    #expect(limited(.right, .bottomRight, from: outside) == CGRect(x: -1300, y: -250, width: 200, height: 300))
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
    // A visible frame above a 60-point Dock and below a 25-point menu bar.
    #expect(WindowGeometry.quartzFrame(from: CGRect(x: 0, y: 60, width: 1440, height: 815), primaryHeight: 900)
            == CGRect(x: 0, y: 25, width: 1440, height: 815))
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

@Test @MainActor func resizeStopsAtTheUsableEdgesOfTheWindowsDisplay() {
    let windows = FakeWindows()
    windows.visibleScreens.append(CGRect(x: 1920, y: 0, width: 1440, height: 900))
    let window = windows.list[0]
    func place(_ frame: CGRect) { windows.list[0] = WindowInfo(id: window.id, name: window.name, frame: frame) }
    var settings = WindowPreferences()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation(), preferences: { settings })
    controller.handle(.enter)
    place(CGRect(x: 30, y: 40, width: 400, height: 300))
    controller.handle(.digit(5))
    controller.handle(.resize(.left, .bottomRight))
    #expect(windows.frames.last == CGRect(x: 0, y: 40, width: 430, height: 300))
    // The menu bar stops the top edge, and held keys stay there.
    for _ in 0..<2 { controller.handle(.resize(.up, .bottomRight)) }
    #expect(windows.frames.last == CGRect(x: 0, y: 25, width: 430, height: 315))
    for direction in [Direction.right, .down] {
        controller.handle(.digit(9))
        controller.handle(.digit(9))
        controller.handle(.resize(direction, .topLeft))
    }
    #expect(windows.frames.last == windows.visibleScreens[0])
    // Moves are not limited, and an edge already past the display stays put.
    controller.handle(.move(.left))
    controller.handle(.resize(.left, .bottomRight))
    #expect(windows.frames.last == windows.visibleScreens[0].offsetBy(dx: -20, dy: 0))
    // The display containing most of the window sets the limits.
    place(CGRect(x: 2000, y: 100, width: 400, height: 300))
    controller.handle(.digit(9))
    controller.handle(.resize(.left, .bottomRight))
    #expect(windows.frames.last == CGRect(x: 1920, y: 100, width: 480, height: 300))
    settings = WindowPreferences(resizeStopsAtDisplayEdges: false)
    controller.handle(.digit(9))
    controller.handle(.resize(.left, .bottomRight))
    #expect(windows.frames.last == CGRect(x: 1740, y: 100, width: 660, height: 300))
}

@Test @MainActor func stepsGlideUnlessTurnedOffAndDisplayMovesJump() {
    let windows = FakeWindows()
    windows.screens.append(CGRect(x: 1920, y: 0, width: 1440, height: 900))
    var settings = WindowPreferences()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation(), preferences: { settings })
    controller.handle(.enter)
    controller.handle(.move(.right))
    controller.handle(.resize(.down, .topLeft))
    controller.handle(.nextScreen)
    settings = WindowPreferences(animatesSteps: false)
    controller.handle(.resize(.left, .bottomRight))
    #expect(windows.animations == [true, true, false, false])
}

@Test @MainActor func undoRestoresEarlierFramesAndRedoReappliesThem() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    let original = windows.list[0].frame
    controller.handle(.enter)
    controller.handle(.move(.right))
    let moved = windows.list[0].frame
    controller.handle(.resize(.down, .topLeft))
    let resized = windows.list[0].frame
    controller.handle(.undo)
    #expect(windows.list[0].frame == moved)
    // Undo leaves numbered selection like the other window commands.
    controller.handle(.quickSwitch)
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
    #expect(controller.mode == .command)
    #expect(ui.guides.isEmpty)
    let applied = windows.frames.count
    controller.handle(.undo)
    #expect(windows.frames.count == applied)
    controller.handle(.redo)
    #expect(windows.list[0].frame == moved)
    controller.handle(.redo)
    #expect(windows.list[0].frame == resized)
    controller.handle(.redo)
    #expect(windows.frames.count == applied + 2)
    // Undo and redo wait for command mode.
    controller.handle(.escape)
    controller.handle(.undo)
    #expect(windows.list[0].frame == resized)
    #expect(ui.errors.isEmpty)
}

@Test @MainActor func repeatedStepsUndoTogetherUntilACountOrAnotherCommand() {
    let windows = FakeWindows()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    let original = windows.list[0].frame
    controller.handle(.enter)
    // Taps or a held key repeating one step form a single change.
    for _ in 0..<5 { controller.handle(.move(.right)) }
    let slidRight = windows.list[0].frame
    for _ in 0..<3 { controller.handle(.move(.down)) }
    let slidDown = windows.list[0].frame
    // A count makes its own change, and a later step does not join it.
    controller.handle(.digit(3))
    controller.handle(.move(.down))
    let counted = windows.list[0].frame
    controller.handle(.move(.down))
    #expect(windows.list[0].frame == original.offsetBy(dx: 100, dy: 140))
    for expected in [counted, slidDown, slidRight, original] {
        controller.handle(.undo)
        #expect(windows.list[0].frame == expected)
    }
    // Leaving command mode ends a change.
    controller.handle(.move(.left))
    controller.handle(.escape)
    controller.handle(.enter)
    controller.handle(.move(.left))
    controller.handle(.undo)
    #expect(windows.list[0].frame == original.offsetBy(dx: -20, dy: 0))
    // So does any other command in between.
    controller.handle(.move(.left))
    controller.handle(.redo)
    controller.handle(.move(.left))
    controller.handle(.undo)
    #expect(windows.list[0].frame == original.offsetBy(dx: -40, dy: 0))
}

@Test @MainActor func eachWindowKeepsItsOwnHistory() {
    let windows = FakeWindows()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    let first = windows.list[0], second = windows.list[1]
    controller.handle(.enter)
    controller.handle(.move(.right))
    // The same step on another window starts that window's own change.
    windows.list.swapAt(0, 1)
    controller.handle(.move(.right))
    controller.handle(.move(.right))
    controller.handle(.undo)
    #expect(windows.list[0].frame == second.frame)
    #expect(windows.list[1].frame == first.frame.offsetBy(dx: 20, dy: 0))
    let applied = windows.frames.count
    controller.handle(.undo)
    #expect(windows.frames.count == applied)
    windows.list.swapAt(0, 1)
    controller.handle(.undo)
    #expect(windows.list[0].frame == first.frame)
    windows.list.swapAt(0, 1)
    controller.handle(.redo)
    #expect(windows.list[0].frame == second.frame.offsetBy(dx: 40, dy: 0))
}

@Test @MainActor func countsTravelSeveralChangesAndANewChangeClearsRedo() {
    let windows = FakeWindows()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    let original = windows.list[0].frame
    controller.handle(.enter)
    controller.handle(.move(.right))
    let moved = windows.list[0].frame
    controller.handle(.move(.down))
    controller.handle(.resize(.right, .topLeft))
    let last = windows.list[0].frame
    controller.handle(.digit(2))
    controller.handle(.undo)
    #expect(windows.list[0].frame == moved)
    // Counts beyond the history stop at its end.
    controller.handle(.digit(9))
    controller.handle(.redo)
    #expect(windows.list[0].frame == last)
    controller.handle(.digit(9))
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
    controller.handle(.move(.up))
    let applied = windows.frames.count
    controller.handle(.redo)
    #expect(windows.frames.count == applied)
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
}

@Test @MainActor func undoGlidesLikeTheChangesItPassesAndFollowsTheSetting() {
    let windows = FakeWindows()
    windows.screens.append(CGRect(x: 1920, y: 0, width: 1440, height: 900))
    var settings = WindowPreferences()
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation(), preferences: { settings })
    let original = windows.list[0].frame
    controller.handle(.enter)
    controller.handle(.move(.right))
    let moved = windows.list[0].frame
    controller.handle(.nextScreen)
    controller.handle(.undo)
    #expect(windows.list[0].frame == moved)
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
    // Passing a display move in one count jumps the whole way.
    controller.handle(.digit(2))
    controller.handle(.redo)
    #expect(windows.list[0].frame == windows.screens[1])
    controller.handle(.digit(2))
    controller.handle(.undo)
    controller.handle(.redo)
    settings = WindowPreferences(animatesSteps: false)
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
    #expect(windows.animations == [true, false, false, true, false, false, true, false])
}

@Test @MainActor func rejectedChangesLeaveTheHistoryAlone() {
    let windows = FakeWindows()
    let ui = FakePresentation()
    let controller = CommandCoordinator(windows: windows, presentation: ui)
    let original = windows.list[0].frame
    controller.handle(.enter)
    controller.handle(.move(.right))
    windows.frameFailure = .unsupportedOperation
    controller.handle(.undo)
    #expect(ui.errors.last as? WindowFailure == .unsupportedOperation)
    windows.frameFailure = nil
    controller.handle(.redo)
    #expect(windows.frames.count == 1)
    controller.handle(.undo)
    #expect(windows.list[0].frame == original)
    // A move the window rejects is not a change, so redo remains.
    windows.frameFailure = .unsupportedOperation
    controller.handle(.move(.left))
    windows.frameFailure = nil
    controller.handle(.redo)
    #expect(windows.list[0].frame == original.offsetBy(dx: 20, dy: 0))
}

@Test @MainActor func undoAndRedoKeepFramesSetByOtherMeans() {
    let windows = FakeWindows()
    let window = windows.list[0]
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    controller.handle(.enter)
    controller.handle(.move(.right))
    let dragged = CGRect(x: 500, y: 400, width: 640, height: 480)
    windows.list[0] = WindowInfo(id: window.id, name: window.name, frame: dragged)
    controller.handle(.undo)
    #expect(windows.list[0].frame == window.frame)
    controller.handle(.redo)
    #expect(windows.list[0].frame == dragged)
}

@Test @MainActor func stepsThatChangeNothingAreNotUndone() {
    let windows = FakeWindows()
    let window = windows.list[0]
    func place(_ frame: CGRect) { windows.list[0] = WindowInfo(id: window.id, name: window.name, frame: frame) }
    let controller = CommandCoordinator(windows: windows, presentation: FakePresentation())
    controller.handle(.enter)
    controller.handle(.move(.right))
    // The top edge already touches the menu bar, so this resize changes nothing.
    let atMenuBar = CGRect(x: 20, y: 25, width: 400, height: 300)
    place(atMenuBar)
    controller.handle(.resize(.up, .bottomRight))
    #expect(windows.list[0].frame == atMenuBar)
    // Once the window moves away, the same resize is a change of its own.
    let lowered = atMenuBar.offsetBy(dx: 0, dy: 100)
    place(lowered)
    controller.handle(.resize(.up, .bottomRight))
    controller.handle(.undo)
    #expect(windows.list[0].frame == lowered)
    controller.handle(.undo)
    #expect(windows.list[0].frame == window.frame)
}

@Test func historyKeepsTheLatestChangesOfRecentlyUsedWindows() {
    var history = UndoHistory(depth: 2, windowLimit: 2)
    let ids = (0..<3).map { _ in UUID() }
    let frames = (0..<4).map { CGRect(x: $0 * 10, y: 0, width: 100, height: 100) }
    for frame in frames.prefix(3) { history.record(frame, canGlide: true, for: ids[0]) }
    #expect(history.travel(.undo, count: 9, for: ids[0], from: frames[3])
            == UndoHistory.Entry(frame: frames[1], canGlide: true))
    #expect(history.travel(.undo, count: 1, for: ids[0], from: frames[1]) == nil)
    #expect(history.travel(.redo, count: 9, for: ids[0], from: frames[1])?.frame == frames[3])
    // A third window forgets the least recently used one.
    history.record(frames[0], canGlide: false, for: ids[1])
    #expect(history.travel(.undo, count: 1, for: ids[0], from: frames[3])?.frame == frames[2])
    history.record(frames[0], canGlide: true, for: ids[2])
    #expect(history.travel(.undo, count: 1, for: ids[1], from: frames[1]) == nil)
    #expect(history.travel(.undo, count: 1, for: ids[0], from: frames[2])?.frame == frames[1])
}

private func glide(from start: CGRect, to target: CGRect, retargets: [Int: CGRect] = [:]) -> [CGRect] {
    var motion = FrameMotion(from: start, to: target, smoothTime: 1.0 / 30)
    var frames: [CGRect] = []
    while (!motion.isFinished || retargets.keys.contains(where: { $0 >= frames.count })) && frames.count < 600 {
        if let next = retargets[frames.count] { motion.retarget(next) }
        frames.append(motion.advance(by: 1.0 / 60))
    }
    return frames
}

@Test func aStepGlidesIntoPlaceWithoutPassingIt() {
    let start = CGRect(x: 100, y: 100, width: 400, height: 300)
    let moved = start.offsetBy(dx: 20, dy: 0)
    let frames = glide(from: start, to: moved)
    #expect((4...8).contains(frames.count))
    #expect(frames.last == moved)
    #expect(frames.allSatisfy { $0.size == start.size && $0.minX <= moved.minX })
    #expect(zip(frames.dropFirst(), frames).allSatisfy { $0.minX > $1.minX })
    // Resizing moves only the free edges; the anchored corner stays exact on every frame.
    let shift = WindowGeometry.apply(.left, to: start, count: 2, anchor: .bottomRight)
    let shiftFrames = glide(from: start, to: shift)
    #expect(shiftFrames.last == shift)
    #expect(shiftFrames.allSatisfy { $0.maxX == start.maxX && $0.maxY == start.maxY && $0.minY == start.minY })
    let option = WindowGeometry.apply(.down, to: start, anchor: .topLeft)
    #expect(glide(from: start, to: option).allSatisfy { $0.origin == start.origin && $0.width == start.width })
    // A fractional frame still moves without changing size.
    let fractional = CGRect(x: 100.5, y: 0, width: 600.25, height: 300)
    #expect(glide(from: fractional, to: fractional.offsetBy(dx: 20, dy: 0)).allSatisfy { $0.size == fractional.size })
}

@Test func heldStepsBlendIntoSteadyMotionAndStopOnTheLastStep() {
    // Key repeats every other 60 Hz frame, 20 points each: 600 points per second.
    let start = CGRect(x: 0, y: 0, width: 400, height: 300)
    let retargets = Dictionary(uniqueKeysWithValues: (1..<20).map { ($0 * 2, start.offsetBy(dx: CGFloat($0 + 1) * 20, dy: 0)) })
    let frames = glide(from: start, to: start.offsetBy(dx: 20, dy: 0), retargets: retargets)
    let steps = zip(frames.dropFirst(), frames).map { $0.minX - $1.minX }
    #expect(frames.last?.minX == 400)
    #expect(steps.allSatisfy { $0 > 0 })
    #expect(steps[4..<36].allSatisfy { (9...11).contains($0) })
    #expect(frames.count < 50)
}

@Test func stalledOrRedirectedGlidesStillEndExactly() {
    let start = CGRect(x: 0, y: 0, width: 400, height: 300)
    let far = start.offsetBy(dx: 100, dy: 0)
    var motion = FrameMotion(from: start, to: far, smoothTime: 1.0 / 30)
    #expect(motion.advance(by: 1) == far)
    #expect(motion.isFinished)
    let reversed = glide(from: start, to: far, retargets: [2: start])
    #expect(reversed.last == start)
    #expect(reversed.allSatisfy { (0...100).contains($0.minX) })
    // A fast glide whose destination moves just ahead stops there instead of sailing past it.
    let near = start.offsetBy(dx: 70, dy: 0)
    let redirected = glide(from: start, to: start.offsetBy(dx: 240, dy: 0), retargets: [1: near])
    #expect(redirected.last == near)
    #expect(redirected.allSatisfy { $0.minX <= near.minX })
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
    var animations: [Bool] = []
    var pointerMoves = 0
    var screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    var visibleScreens = [CGRect(x: 0, y: 25, width: 1920, height: 1000)]
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
    func setFrame(_ frame: CGRect, of id: UUID, animated: Bool) throws {
        try check()
        if let frameFailure { throw frameFailure }
        frames.append(frame)
        animations.append(animated)
        if let index = list.firstIndex(where: { $0.id == id }) {
            let window = list[index]
            list[index] = WindowInfo(id: id, name: window.name, frame: frame, isFocused: window.isFocused)
        }
    }
    func screenFrames() -> [CGRect] { screens }
    func visibleScreenFrames() -> [CGRect] { visibleScreens }
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
    func showSettings() {}
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
