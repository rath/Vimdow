import AppKit
import Testing
import VimdowCore

// Share the serialized suite with search tests: both exercise real key windows.
extension SearchPanelTests {
    private static let items = ["Terminal", "TextEdit", "Time Machine"].map {
        LauncherItem(id: "/Applications/\($0).app", name: $0, kind: .application)
    }

    @MainActor
    private func makeLauncher(queries: @escaping (String) -> Void = { _ in },
                              completions: @escaping (LauncherItem?) -> Void) -> LauncherPanel {
        _ = NSApplication.shared
        let panel = LauncherPanel()
        panel.resultsProvider = { query in
            queries(query)
            return query.isEmpty ? [] : Self.items
        }
        panel.onFinish = { [weak panel] item in completions(item); panel?.hide() }
        return panel
    }

    @MainActor
    private func editor(of panel: LauncherPanel) throws -> (NSTextField, NSTextView) {
        let field = try #require(panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        return (field, try #require(field.currentEditor() as? NSTextView))
    }

    @Test func launcherTypingReRanksThroughTheProviderAndArrowsClamp() throws {
        var queries: [String] = []
        var completions: [LauncherItem?] = []
        let panel = makeLauncher(queries: { queries.append($0) }, completions: { completions.append($0) })
        defer { panel.hide() }
        panel.show()
        let (field, editor) = try editor(of: panel)
        #expect(panel.isVisible && panel.isKeyWindow)
        #expect(panel.results.isEmpty)
        let emptyHeight = panel.frame.height
        let top = panel.frame.maxY
        editor.insertText("te", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(queries.last == "te")
        #expect(panel.results.count == 3)
        #expect(panel.selectedIndex == 0)
        #expect(panel.frame.height > emptyHeight)
        #expect(panel.frame.maxY == top)
        for _ in 0..<5 { #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))) }
        #expect(panel.selectedIndex == 2)
        for _ in 0..<5 { #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))) }
        #expect(panel.selectedIndex == 0)
        editor.selectAll(nil)
        editor.delete(nil)
        #expect(queries.last == "")
        #expect(panel.results.isEmpty)
        #expect(panel.frame.height == emptyHeight)
        #expect(panel.frame.maxY == top)
        #expect(completions.isEmpty)
    }

    @Test func launcherReturnFinishesWithTheSelectedItemExactlyOnce() throws {
        var completions: [LauncherItem?] = []
        let panel = makeLauncher { completions.append($0) }
        defer { panel.hide() }
        panel.show()
        let (field, editor) = try editor(of: panel)
        editor.insertText("t", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(panel.query == "t")
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(completions == [Self.items[1]])
        #expect(!panel.isVisible)
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(completions.count == 1)
    }

    @Test func launcherReturnWithoutResultsIsIgnoredAndEscapeCancels() throws {
        var completions: [LauncherItem?] = []
        let panel = makeLauncher { completions.append($0) }
        defer { panel.hide() }
        panel.show()
        let (field, editor) = try editor(of: panel)
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(completions.isEmpty)
        #expect(panel.isVisible)
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(completions == [nil])
        #expect(!panel.isVisible)
    }

    @Test func launcherMarkedTextKeepsReturnEscapeAndArrowsInsideTheInputMethod() throws {
        var completions: [LauncherItem?] = []
        let panel = makeLauncher { completions.append($0) }
        defer { panel.hide() }
        panel.show()
        let (field, editor) = try editor(of: panel)
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(panel.query == "한")
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
                         #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:))] {
            #expect(!panel.control(field, textView: editor, doCommandBy: selector))
        }
        #expect(completions.isEmpty)
        editor.unmarkText()
        editor.insertText("글", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(panel.query == "한글")
        #expect(panel.results.count == 3)
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(completions == [Self.items[0]])
    }

    @Test func launcherResignKeyCancelsOnceAndShowResetsState() throws {
        var completions: [LauncherItem?] = []
        let panel = makeLauncher { completions.append($0) }
        defer { panel.hide() }
        panel.show()
        let (field, editor) = try editor(of: panel)
        editor.insertText("ti", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(panel.selectedIndex == 1)
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(completions == [nil])
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(completions.count == 1)
        panel.show()
        #expect(panel.query == "")
        #expect(panel.results.isEmpty)
        #expect(panel.selectedIndex == 0)
        #expect(panel.isKeyWindow)
        panel.makeFirstResponder(nil)
        panel.makeFirstResponder(field)
        #expect(completions.count == 1)
    }

    /// Depends on the installed macOS, so it checks shape rather than exact contents.
    @Test func launcherCatalogResolvesHumanPaneNamesAndSkipsExcludedPanes() throws {
        let panes = LauncherScan.settingsPanes()
        #expect(panes.count > 10)
        #expect(panes.allSatisfy { !$0.name.isEmpty && $0.kind == .settingsPane })
        #expect(panes.allSatisfy { !LauncherScan.excludedPaneIDs.contains($0.id) })
        #expect(!panes.contains { $0.name == "PowerPreferences" })
        #expect(panes.contains { LauncherHistory.normalize($0.name) == "wi fi" })
        let battery = try #require(panes.first { $0.id == "com.apple.Battery-Settings.extension" })
        #expect(battery.name != "PowerPreferences")
        #expect(!battery.aliases.isEmpty)
        let applications = LauncherScan.applications()
        #expect(applications.contains { $0.id == "/System/Applications/System Settings.app" })
        #expect(Set(applications.map(\.id)).count == applications.count)
    }
}
