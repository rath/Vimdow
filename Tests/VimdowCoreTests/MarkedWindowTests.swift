import Foundation
import Testing
@testable import VimdowCore

@MainActor
private final class MarkWindows: WindowControlling {
    let items = ["Ghostty", "Chrome", "Chrome", "Slack"].enumerated().map { index, name in
        WindowInfo(id: UUID(), name: name, frame: CGRect(x: index * 300, y: 100, width: 600, height: 500))
    }
    lazy var live = Set(items.map(\.id))
    lazy var visible = items.map(\.id)
    var current: UUID?
    var retained: Set<UUID> = []
    var focused: [UUID] = []
    var pointerMoves = 0
    var closingOnFocus: Set<UUID> = []
    var focusFailure: WindowFailure?
    var scanFailure: WindowFailure?
    var livenessFailures: [UUID: WindowFailure] = [:]

    func windows() throws -> [WindowInfo] {
        if let scanFailure { throw scanFailure }
        return visible.filter { live.contains($0) }.compactMap { id in
            items.first { $0.id == id }.map {
                WindowInfo(id: id, name: $0.name, frame: $0.frame, isFocused: current == id)
            }
        }
    }
    func focusedWindow() throws -> WindowInfo {
        guard let current, live.contains(current), let item = items.first(where: { $0.id == current }) else {
            throw WindowFailure.noFocusedWindow
        }
        return item
    }
    func focus(_ id: UUID, movePointer: Bool) throws {
        if closingOnFocus.contains(id) { live.remove(id) }
        guard live.contains(id) else { throw WindowFailure.unavailableWindow }
        if let focusFailure { throw focusFailure }
        current = id
        focused.append(id)
        if movePointer { pointerMoves += 1 }
    }
    func retainWindows(_ ids: Set<UUID>) { retained = ids }
    func isWindowAlive(_ id: UUID) throws -> Bool {
        if let error = livenessFailures[id] { throw error }
        return live.contains(id)
    }
    func setFrame(_ frame: CGRect, of id: UUID, animated: Bool) throws {}
    func screenFrames() -> [CGRect] { [] }
    func visibleScreenFrames() -> [CGRect] { [] }
}

@MainActor
private final class MarkPresentation: CommandPresenting {
    var notices: [String] = []
    var flashes: [CGRect] = []
    var noticeFrame: CGRect?
    var guides: [WindowInfo] = []
    var errors: [any Error] = []
    func setMode(_ mode: Mode) {}
    func showGuides(_ windows: [WindowInfo]) { guides = windows }
    func hideGuides() { guides = [] }
    func showSearch() {}
    func hideSearch() {}
    func showLauncher() {}
    func hideLauncher() {}
    func showSettings() {}
    func toggleDimming() {}
    func showNotice(_ text: String, near frame: CGRect?) { notices.append(text); noticeFrame = frame }
    func flashWindow(_ frame: CGRect) { flashes.append(frame) }
    func showFailure(_ error: any Error) { errors.append(error) }
    func quit() {}
}

@MainActor
private struct MarkSession {
    let windows = MarkWindows()
    let ui = MarkPresentation()
    let controller: CommandCoordinator
    init() { controller = CommandCoordinator(windows: windows, presentation: ui) }
    func mark(_ index: Int) {
        windows.current = windows.items[index].id
        controller.handle(.enter)
        controller.handle(.toggleMark)
    }
    var ids: [UUID] { windows.items.map(\.id) }
}

@Test @MainActor func marksToggleAndExitWithFeedbackWithoutMovingPointer() {
    let s = MarkSession()
    s.mark(1)
    #expect(s.controller.markedWindows == [s.ids[1]])
    #expect(s.windows.retained == [s.ids[1]])
    #expect(s.controller.mode == .normal)
    #expect(s.ui.notices == ["Marked"])
    #expect(s.ui.noticeFrame == s.windows.items[1].frame)
    s.mark(1)
    #expect(s.controller.markedWindows.isEmpty)
    #expect(s.windows.retained.isEmpty)
    #expect(s.ui.notices == ["Marked", "Unmarked"])
    #expect(s.windows.focused.isEmpty)
    #expect(s.windows.pointerMoves == 0)
}

@Test(arguments: [-1, 1]) @MainActor func twoMarksAlternateAndExcludeOtherWindowsOfTheSameApp(_ step: Int) {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    for _ in 0..<4 { s.controller.handle(.cycleMarked(step)) }
    #expect(s.windows.focused == [s.ids[0], s.ids[1], s.ids[0], s.ids[1]])
    #expect(s.windows.pointerMoves == 0)
    #expect(s.ui.notices.count == 2) // Switching itself stays quiet.
    #expect(s.ui.flashes == [0, 1, 0, 1].map { s.windows.items[$0].frame })
    s.windows.current = s.ids[3]
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[step > 0 ? 0 : 1])
    // Existing full-window cycling still visits the unmarked second Chrome window.
    s.windows.current = s.ids[1]
    s.controller.handle(.cycle(1))
    #expect(s.windows.current == s.ids[2])
    #expect(s.ui.flashes.count == 5) // Whole-window cycling has no flash.
}

@Test(arguments: [-1, 1]) @MainActor func markOrderSurvivesWindowReorderingAndRemarksAppend(_ step: Int) {
    let s = MarkSession()
    s.mark(2)
    s.mark(0)
    s.mark(1)
    s.windows.visible.reverse()
    for _ in 0..<3 { s.controller.handle(.cycleMarked(step)) }
    #expect(s.windows.focused == (step > 0 ? [2, 0, 1] : [0, 2, 1]).map { s.ids[$0] })
    s.mark(0)
    s.mark(0)
    #expect(s.controller.markedWindows == [s.ids[2], s.ids[1], s.ids[0]])
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[step > 0 ? 2 : 1])
}

@Test @MainActor func hiddenMarksSurviveScansAndRejoinInTheirOriginalOrder() {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    s.mark(2)
    s.windows.visible.removeAll { $0 == s.ids[0] }
    s.controller.handle(.cycleMarked(1))
    #expect(s.windows.current == s.ids[1])
    #expect(s.windows.retained == Set(s.ids.prefix(3)))
    s.windows.visible.append(s.ids[0])
    s.windows.current = s.ids[2]
    s.controller.handle(.cycleMarked(1))
    #expect(s.windows.current == s.ids[0])
    // Closing a hidden window is different from merely hiding it.
    s.windows.visible.removeAll { $0 == s.ids[1] }
    s.windows.live.remove(s.ids[1])
    s.controller.handle(.cycleMarked(1))
    #expect(s.controller.markedWindows == [s.ids[0], s.ids[2]])
    #expect(!s.windows.retained.contains(s.ids[1]))
}

@Test(arguments: [-1, 1]) @MainActor func emptyAndSingleVisibleMarksDoNotSwitchToUnmarkedWindows(_ step: Int) {
    let s = MarkSession()
    s.controller.handle(.cycleMarked(step))
    #expect(s.ui.notices.last == "No marked windows")
    s.mark(0)
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.focused.isEmpty)
    #expect(s.ui.flashes.isEmpty)
    s.windows.current = s.ids[3]
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[0])
    s.windows.visible.removeAll { $0 == s.ids[0] }
    s.windows.current = s.ids[3]
    s.controller.handle(.cycleMarked(step))
    #expect(s.ui.notices.last == "No marked windows on this desktop")
    #expect(s.windows.current == s.ids[3])
    #expect(s.controller.markedWindows == [s.ids[0]])
    s.windows.live.remove(s.ids[0])
    s.controller.handle(.cycleMarked(step))
    #expect(s.ui.notices.last == "No marked windows")
    #expect(s.windows.retained.isEmpty)
}

@Test(arguments: [-1, 1]) @MainActor func closingBetweenScanAndFocusContinuesToNextMark(_ step: Int) {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    s.mark(2)
    s.windows.current = s.ids[step > 0 ? 2 : 1]
    s.windows.closingOnFocus = [s.ids[0]]
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[step > 0 ? 1 : 2])
    #expect(s.controller.markedWindows == [s.ids[1], s.ids[2]])
    #expect(s.ui.errors.isEmpty)
    #expect(s.ui.flashes == [s.windows.items[step > 0 ? 1 : 2].frame])
    s.windows.closingOnFocus = [s.ids[1], s.ids[2]]
    s.windows.current = s.ids[3]
    s.controller.handle(.cycleMarked(step))
    #expect(s.controller.markedWindows.isEmpty)
    #expect(s.ui.notices.last == "No marked windows")
}

@Test(arguments: [-1, 1]) @MainActor func transientLivenessErrorsPreserveMarksButPermissionErrorsStop(_ step: Int) {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    s.windows.livenessFailures[s.ids[0]] = .accessibility(-25204)
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[0])
    #expect(s.controller.markedWindows == [s.ids[0], s.ids[1]])
    s.windows.livenessFailures[s.ids[0]] = .permissionDenied
    s.controller.handle(.enter)
    s.controller.handle(.cycleMarked(step))
    #expect(s.ui.errors.last as? WindowFailure == .permissionDenied)
    #expect(s.controller.mode == .normal)
    #expect(s.controller.markedWindows.count == 2)
}

@Test(arguments: [WindowFailure.permissionDenied, .unavailableWindow, .unsupportedOperation, .accessibility(-25204)], [-1, 1])
@MainActor func focusErrorsKeepMarksAndReleaseModalInput(_ error: WindowFailure, _ step: Int) {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    s.windows.focusFailure = error
    s.controller.handle(.enter)
    s.controller.handle(.quickSwitch)
    s.controller.handle(.cycleMarked(step))
    #expect(s.controller.mode == .normal)
    #expect(s.ui.guides.isEmpty)
    #expect(s.controller.markedWindows.count == 2)
    #expect(s.ui.errors.last as? WindowFailure == error)
    #expect(s.ui.flashes.isEmpty)
}

@Test(arguments: [-1, 1]) @MainActor func markedCommandsIgnoreCountsAndRespectInputModesAndSequences(_ step: Int) {
    let s = MarkSession()
    s.windows.current = s.ids[0]
    s.controller.handle(.toggleMark) // Normal typing must never mark a window.
    #expect(s.controller.markedWindows.isEmpty)
    s.controller.handle(.enter)
    s.controller.handle(.digit(9))
    s.controller.handle(.toggleMark)
    s.mark(1)
    s.mark(2)
    s.controller.handle(.enter)
    s.controller.handle(.digit(2))
    s.controller.handle(.cycleMarked(step))
    #expect(s.windows.current == s.ids[step > 0 ? 0 : 1])
    #expect(s.controller.mode == .normal)
    s.controller.handle(.enter)
    s.controller.handle(.sequence(.g))
    s.controller.handle(.toggleMark) // Invalid second key cancels the sequence.
    #expect(s.controller.markedWindows.count == 3)
    s.controller.handle(.search)
    let before = s.windows.focused
    s.controller.handle(.cycleMarked(step))
    s.controller.handle(.toggleMark)
    #expect(s.controller.mode == .search)
    #expect(s.windows.focused == before)
    s.controller.setSettingsActive(true)
    let afterSearch = s.windows.focused
    s.controller.handle(.cycleMarked(step))
    s.controller.handle(.toggleMark)
    #expect(s.controller.mode == .settings)
    #expect(s.windows.focused == afterSearch)
    #expect(s.controller.markedWindows.count == 3)
}

@Test(arguments: [-1, 1]) @MainActor func scanErrorsPreserveMarksAndNewSessionsStartEmpty(_ step: Int) {
    let s = MarkSession()
    s.mark(0)
    s.windows.scanFailure = .accessibility(-25204)
    s.controller.handle(.cycleMarked(step))
    #expect(s.controller.markedWindows == [s.ids[0]])
    #expect(s.ui.errors.count == 1)
    let fresh = MarkSession()
    #expect(fresh.controller.markedWindows.isEmpty)
}

@Test @MainActor func backwardCyclingSkipsHiddenMarksAndRestoresRegistrationOrder() {
    let s = MarkSession()
    s.mark(0)
    s.mark(1)
    s.mark(2)
    s.windows.current = s.ids[0]
    s.windows.visible.removeAll { $0 == s.ids[2] }
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.current == s.ids[1])
    #expect(s.windows.retained == Set(s.ids.prefix(3)))
    s.windows.visible.insert(s.ids[2], at: 0)
    s.controller.handle(.cycleMarked(-1))
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.focused == [s.ids[1], s.ids[0], s.ids[2]])
    s.windows.visible.removeAll { $0 == s.ids[1] }
    s.windows.live.remove(s.ids[1])
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.current == s.ids[0])
    #expect(s.controller.markedWindows == [s.ids[0], s.ids[2]])
}

@Test @MainActor func changingDirectionAndEnteringFromOutsideUseRegistrationOrder() {
    let s = MarkSession()
    s.mark(2)
    s.mark(0)
    s.mark(1)
    s.windows.current = s.ids[3]
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.current == s.ids[1])
    s.controller.handle(.cycleMarked(1))
    #expect(s.windows.current == s.ids[2])
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.current == s.ids[1])
    s.windows.current = nil
    s.controller.handle(.cycleMarked(1))
    #expect(s.windows.current == s.ids[2])
    s.windows.current = nil
    s.controller.handle(.cycleMarked(-1))
    #expect(s.windows.current == s.ids[1])
    #expect(s.windows.pointerMoves == 0)
}

@Test(arguments: [-1, 1]) @MainActor func markedFocusIntegrationOnlyRunsAfterSuccessfulSwitches(_ step: Int) {
    let s = MarkSession()
    var destinations: [UUID] = []
    s.controller.onMarkedWindowFocus = { destinations.append($0) }
    s.controller.handle(.cycleMarked(step)) // No marks.
    s.mark(0)
    s.controller.handle(.cycleMarked(step)) // Already focused single mark.
    #expect(destinations.isEmpty)
    s.mark(1)
    s.controller.handle(.cycleMarked(step))
    #expect(destinations == [s.ids[0]])
    s.controller.handle(.cycle(1)) // Ordinary switching must not trigger the integration.
    #expect(destinations.count == 1)
    s.windows.focusFailure = .unavailableWindow
    s.controller.handle(.cycleMarked(step))
    #expect(destinations.count == 1)
    s.controller.handle(.enter)
    s.controller.handle(.search)
    s.controller.handle(.cycleMarked(step))
    s.controller.setSettingsActive(true)
    s.controller.handle(.cycleMarked(step))
    #expect(destinations.count == 1)
}
