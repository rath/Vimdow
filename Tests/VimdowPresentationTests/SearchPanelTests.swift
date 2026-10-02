import AppKit
import Testing
import VimdowCore

struct GuideLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func target(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x - 200, y: y - 150, width: 400, height: 300)
    }

    private func expectSeparated(_ frames: [CGRect], in bounds: CGRect) {
        for (index, frame) in frames.enumerated() {
            #expect(bounds.contains(frame))
            #expect(frame.size == CGSize(width: 160, height: 160))
            for other in frames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
                #expect(other.minX - frame.maxX >= 12 || frame.minX - other.maxX >= 12 ||
                        other.minY - frame.maxY >= 12 || frame.minY - other.maxY >= 12)
            }
        }
    }

    @Test func isolatedBadgesStayCenteredIncludingSmallWindows() {
        let targets = [target(400, 500), CGRect(x: 1000, y: 400, width: 50, height: 50)]
        let frames = GuideLayout.frames(for: targets, screens: [screen])
        for (frame, target) in zip(frames, targets) {
            #expect(frame.midX == target.midX && frame.midY == target.midY)
        }
        expectSeparated(frames, in: screen)
        #expect(GuideLayout.frames(for: [], screens: [screen]).isEmpty)
    }

    @Test func coincidentPairUsesNumberOrderFromLeftToRight() {
        let frames = GuideLayout.frames(for: Array(repeating: target(500, 500), count: 2), screens: [screen])
        expectSeparated(frames, in: screen)
        #expect(frames[0].midX == 414 && frames[1].midX == 586)
        #expect(frames.allSatisfy { $0.midY == 500 })
    }

    @Test func nineCoincidentBadgesFitAtDisplayEdgesInReadingOrder() {
        for center in [CGPoint(x: 960, y: 540), .zero, CGPoint(x: 1920, y: 1080)] {
            let frames = GuideLayout.frames(for: Array(repeating: target(center.x, center.y), count: 9),
                                            screens: [screen])
            expectSeparated(frames, in: screen)
            for index in 1..<9 {
                if index % 3 == 0 {
                    #expect(frames[index].midY < frames[index - 1].midY)
                } else {
                    #expect(frames[index].midX > frames[index - 1].midX)
                    #expect(frames[index].midY == frames[index - 1].midY)
                }
            }
        }
    }

    @Test func regroupingResolvesNewCollisionsWithoutMovingAnIsolatedBadge() {
        let targets = [target(500, 500), target(500, 500), target(740, 500), target(1500, 500)]
        let frames = GuideLayout.frames(for: targets, screens: [screen])
        expectSeparated(frames, in: screen)
        #expect(frames[3].midX == 1500 && frames[3].midY == 500)
        #expect(frames[2].midY < frames[0].midY)
        #expect(GuideLayout.frames(for: targets, screens: [screen]) == frames)
    }

    @Test func usesDisplayWithLargestIntersectionAndSupportsNegativeCoordinates() {
        let left = CGRect(x: -1200, y: 0, width: 1200, height: 900)
        let above = CGRect(x: 0, y: 1080, width: 1200, height: 900)
        let targets = [CGRect(x: -1100, y: -200, width: 400, height: 300),
                       CGRect(x: -300, y: 400, width: 400, height: 300),
                       CGRect(x: 100, y: 1880, width: 400, height: 300)]
        let frames = GuideLayout.frames(for: targets, screens: [screen, left, above])
        #expect(left.contains(frames[0]) && left.contains(frames[1]))
        #expect(above.contains(frames[2]))
        #expect(frames[0].minY == left.minY)
        #expect(frames[2].maxY == above.maxY)
    }

    @Test func narrowDisplayUsesATallerGrid() {
        let portrait = CGRect(x: -400, y: 0, width: 400, height: 1000)
        let frames = GuideLayout.frames(for: Array(repeating: target(-200, 500), count: 9),
                                        screens: [portrait])
        expectSeparated(frames, in: portrait)
    }
}

/// Exercises the real AppKit field editor; run on an interactive Mac.
@Suite(.serialized)
@MainActor
struct SearchPanelTests {
    @Test func guidesPreserveInputAndReplacePreviousPage() throws {
        _ = NSApplication.shared
        let search = SearchPanel()
        let guides = GuideWindows()
        defer { guides.hide(); search.hide() }
        search.show()
        let keyWindow = NSApp.keyWindow
        let targets = (0..<9).map { _ in
            WindowInfo(id: UUID(), name: "Test", frame: CGRect(x: 100, y: 100, width: 600, height: 500))
        }
        guides.show(targets)
        let firstPage = NSApp.windows.compactMap { $0 as? GuidePanel }.filter(\.isVisible)
        #expect(firstPage.count == 9)
        #expect(NSApp.keyWindow === keyWindow)
        for panel in firstPage {
            #expect(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents)
            #expect(panel.frame.size == CGSize(width: 160, height: 160))
        }
        #expect(Set(firstPage.compactMap { $0.contentView?.accessibilityLabel() }) ==
                Set((1...9).map(String.init)))
        guides.show(Array(targets.prefix(2)))
        #expect(firstPage.allSatisfy { !$0.isVisible })
        #expect(NSApp.windows.compactMap { $0 as? GuidePanel }.filter(\.isVisible).count == 2)
        #expect(NSApp.keyWindow === keyWindow)
        guides.hide()
        #expect(!NSApp.windows.contains { $0 is GuidePanel && $0.isVisible })
    }

    @Test func focusFlashPreservesInputAndRapidSwitchingReplacesThePreviousPulse() async throws {
        _ = NSApplication.shared
        let search = SearchPanel()
        let flash = FocusFlash()
        defer { flash.hide(); search.hide() }
        search.show()
        let keyWindow = NSApp.keyWindow
        flash.show(CGRect(x: 100, y: 100, width: 600, height: 500))
        #expect(flash.isVisible)
        #expect(!flash.canBecomeKey && !flash.canBecomeMain)
        #expect(flash.ignoresMouseEvents)
        #expect(NSApp.keyWindow === keyWindow)
        try await Task.sleep(for: .milliseconds(240))
        #expect(flash.isVisible) // Feedback continues beyond the first pulse.
        let next = CGRect(x: 700, y: 200, width: 400, height: 300)
        flash.show(next)
        let primary = try #require(NSScreen.screens.first)
        #expect(flash.frame == CGRect(x: 702, y: primary.frame.height - 498, width: 396, height: 296))
        try await Task.sleep(for: .milliseconds(220))
        #expect(flash.isVisible) // The first pulse's timer must not dismiss the second.
        #expect(NSApp.keyWindow === keyWindow)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!flash.isVisible)
        flash.show(next)
        flash.hide()
        #expect(!flash.isVisible)
    }

    @Test func markNoticeNeverTakesInputAndNewMessagesReplaceTheDismissalTimer() async throws {
        _ = NSApplication.shared
        let search = SearchPanel()
        let notice = StatusNotice()
        defer { notice.hide(); search.hide() }
        search.show()
        let keyWindow = NSApp.keyWindow
        notice.show("Marked", near: CGRect(x: 100, y: 100, width: 600, height: 500))
        #expect(notice.isVisible)
        #expect(!notice.canBecomeKey && !notice.canBecomeMain)
        #expect(notice.ignoresMouseEvents)
        #expect(NSApp.keyWindow === keyWindow)
        try await Task.sleep(for: .milliseconds(500))
        notice.show("No marked windows on this desktop", near: nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(notice.isVisible)
        #expect(NSApp.keyWindow === keyWindow)
        let label = try #require(notice.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.stringValue == "No marked windows on this desktop")
        #expect(label.frame.width >= label.intrinsicContentSize.width)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!notice.isVisible)
    }

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
