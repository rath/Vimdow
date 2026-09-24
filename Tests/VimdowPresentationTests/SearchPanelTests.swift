import AppKit
import Testing

/// Exercises the real AppKit field editor; run on an interactive Mac.
@Suite(.serialized)
@MainActor
struct SearchPanelTests {
    @Test func showingAndChangingFirstResponderDoesNotSubmit() async throws {
        _ = NSApplication.shared
        let panel = SearchPanel()
        var completions: [String?] = []
        panel.onFinish = { [weak panel] query in completions.append(query); panel?.hide() }
        defer { panel.hide() }

        panel.show()
        let field = try #require(panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(completions.isEmpty)
        #expect(panel.isVisible)
        #expect(panel.isKeyWindow)
        // This responder transition triggered textDidEndEditing and submitted an
        // empty query from inside show() in the original implementation.
        panel.makeFirstResponder(nil)
        panel.makeFirstResponder(field)
        #expect(completions.isEmpty)
        #expect(panel.isVisible)
        _ = try #require(field.currentEditor() as? NSTextView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(completions.isEmpty)
        #expect(panel.isVisible)
        #expect(panel.isKeyWindow)
    }

    @Test func returnSubmitsLiveEditorTextExactlyOnce() throws {
        _ = NSApplication.shared
        let panel = SearchPanel()
        var completions: [String?] = []
        panel.onFinish = { [weak panel] query in completions.append(query); panel?.hide() }
        defer { panel.hide() }
        panel.show()
        let field = try #require(panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("한글 Terminal", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(completions.count == 1)
        #expect(completions == ["한글 Terminal"])
        #expect(!panel.isVisible)
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(completions.count == 1)
    }

    @Test func markedTextKeepsReturnAndEscapeInsideTheInputMethod() throws {
        _ = NSApplication.shared
        let panel = SearchPanel()
        var completions: [String?] = []
        panel.onFinish = { [weak panel] query in completions.append(query); panel?.hide() }
        defer { panel.hide() }
        panel.show()
        let field = try #require(panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(!panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(!panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(completions.isEmpty)
        editor.unmarkText()
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(completions.count == 1)
        #expect(completions == [nil])
        #expect(!panel.isVisible)
    }
}
