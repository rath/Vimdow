import AppKit
import VimdowCore

@MainActor
final class GuideWindows {
    private var windows: [NSPanel] = []

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func show(_ targets: [WindowInfo]) {
        hide()
        guard let primary = NSScreen.screens.first else { return }
        for (index, target) in targets.enumerated() {
            let quartzFrame = CGRect(x: target.frame.minX + 4, y: target.frame.minY + 4, width: 36, height: 36)
            let frame = WindowGeometry.appKitFrame(from: quartzFrame, primaryHeight: primary.frame.height)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.4)
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let label = NSTextField(labelWithString: String(index + 1))
            label.font = .systemFont(ofSize: 28)
            label.textColor = .white
            label.alignment = .center
            label.frame = CGRect(x: 0, y: 1, width: 36, height: 34)
            panel.contentView?.addSubview(label)
            panel.orderFrontRegardless()
            windows.append(panel)
        }
    }
}

@MainActor
final class SearchPanel: NSPanel, NSWindowDelegate, NSTextFieldDelegate {
    var onFinish: ((String?) -> Void)?
    private let field = NSTextField(string: "")
    private var isSearching = false

    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 480, height: 70),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        delegate = self
        field.font = .systemFont(ofSize: 24)
        field.placeholderString = "Application name to switch"
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        field.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(field)
        if let contentView {
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                field.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ])
        }
    }

    func show() {
        field.stringValue = ""
        isSearching = true
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let screen {
            setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - frame.width / 2,
                                   y: screen.visibleFrame.midY - frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func hide() {
        isSearching = false
        orderOut(nil)
    }

    @objc private func submit() { finish(field.stringValue) }

    func windowDidResignKey(_ notification: Notification) { finish(nil) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText() else { return false }
        finish(nil)
        return true
    }

    private func finish(_ query: String?) {
        guard isSearching else { return }
        isSearching = false
        onFinish?(query)
    }
}
