import Foundation
import Testing

private let tmuxClient = TmuxClient(pid: 30, tty: "/dev/ttys001", pane: "%12", focused: true)
private let tmuxTarget = TmuxPaneTarget(executable: "/usr/local/bin/tmux", client: tmuxClient, targetsPane: true)

@Test func tmuxParsingRequiresAttachedClientAndFocusReporting() {
    let clients = TmuxClient.parse("""
    30\t/dev/ttys001\t%12\tattached,focused,UTF-8\t256,focus,RGB
    31\t/dev/ttys002\t%13\tattached,UTF-8\tfocus
    32\t/dev/ttys003\t%14\tattached,focused\t256,RGB
    33\t/dev/ttys004\t%15\tfocused\tfocus
    garbage
    34\t/dev/ttys005\tnot-a-pane\tattached,focused\tfocus
    """
    )
    #expect(clients.count == 4)
    #expect(clients.filter(\.focused) == [tmuxClient])
}

@Test func tmuxSelectionRequiresUniqueFocusedDescendantOfDestinationApp() {
    let other = TmuxClient(pid: 40, tty: "/dev/ttys002", pane: "%13", focused: true)
    let parents: [Int32: Int32] = [30: 20, 20: 10, 10: 1, 40: 50, 50: 1]
    #expect(TmuxClient.select(from: [tmuxClient, other], terminalPID: 10, parents: parents) == tmuxClient)
    #expect(TmuxClient.select(from: [tmuxClient], terminalPID: 50, parents: parents) == nil)
    #expect(TmuxClient.select(from: [tmuxClient, other], terminalPID: 10, parents: [30: 10, 40: 10]) == nil)
    #expect(TmuxClient.select(from: [tmuxClient], terminalPID: 10, parents: [30: 20, 20: 30]) == nil)
    #expect(TmuxClient.select(from: [tmuxClient], terminalPID: 10, parents: [:]) == nil)
}

@Test func tmuxTargetsClientOnStableReleasesAndPaneOnNewReleases() {
    #expect(tmuxTarget.arguments == ["display-panes", "-t", "%12"])
    let older = TmuxPaneTarget(executable: tmuxTarget.executable, client: tmuxClient, targetsPane: false)
    #expect(older.arguments == ["display-panes", "-b", "-t", "/dev/ttys001"])
}

private actor TmuxProbe {
    var resolutions = 0
    var shown: [TmuxPaneTarget] = []
    var waiters: [CheckedContinuation<TmuxPaneTarget?, Never>] = []

    func resolve(_ pid: Int32) async -> TmuxPaneTarget? {
        resolutions += 1
        return await withCheckedContinuation { waiters.append($0) }
    }
    func finish() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: tmuxTarget) }
    }
    func display(_ target: TmuxPaneTarget) { shown.append(target) }
}

@MainActor private final class TerminalFocus {
    var focused = true
}

@Test @MainActor func tmuxDisplayRechecksFocusAfterLookup() async throws {
    let probe = TmuxProbe()
    let focus = TerminalFocus()
    let integration = TmuxPaneDisplay(delay: .zero, resolve: { await probe.resolve($0) },
                                      display: { await probe.display($0) })
    integration.isEnabled = true
    integration.show(terminalPID: 10) { focus.focused }
    try await waitUntil { await probe.resolutions == 1 }
    focus.focused = false
    await probe.finish()
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.shown.isEmpty)
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 2 }
    await probe.finish()
    try await waitUntil { await probe.shown.count == 1 }
    #expect(await probe.shown == [tmuxTarget])
}

@Test @MainActor func rapidSwitchesCancelOlderTmuxLookupsAndOrdinaryFocusCanCancel() async throws {
    let probe = TmuxProbe()
    let integration = TmuxPaneDisplay(delay: .zero, resolve: { await probe.resolve($0) },
                                      display: { await probe.display($0) })
    integration.isEnabled = true
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 1 }
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 2 }
    await probe.finish()
    try await waitUntil { await probe.shown.count == 1 }
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 3 }
    integration.cancel()
    await probe.finish()
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.shown.count == 1)
}

@Test @MainActor func tmuxOptInDefaultsOffAndDisablingCancelsPendingWork() async throws {
    let probe = TmuxProbe()
    let integration = TmuxPaneDisplay(delay: .zero, resolve: { await probe.resolve($0) },
                                      display: { await probe.display($0) })
    #expect(!integration.isEnabled)
    integration.show(terminalPID: 10) { true }
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.resolutions == 0)
    integration.isEnabled = true
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 1 }
    integration.isEnabled = false
    await probe.finish()
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.shown.isEmpty)
    integration.isEnabled = true
    integration.show(terminalPID: 10) { true }
    try await waitUntil { await probe.resolutions == 2 }
    await probe.finish()
    try await waitUntil { await probe.shown.count == 1 }
}

@MainActor private func waitUntil(_ predicate: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for tmux integration")
}
