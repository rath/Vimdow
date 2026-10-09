import AppKit
import VimdowCore

/// A nonactivating panel with a query field and up to eight result rows. Like
/// SearchPanel, it takes keyboard focus without activating Vimdow and leaves
/// Return and Escape to the input method while text is being composed.
@MainActor
final class LauncherPanel: NSPanel, NSWindowDelegate, NSTextFieldDelegate {
    static let maxResults = 8
    private static let width: CGFloat = 600
    private static let headerHeight: CGFloat = 62
    private static let rowHeight: CGFloat = 44
    private static let listInset: CGFloat = 8
    private static let listSpacing: CGFloat = 6

    var resultsProvider: ((String) -> [LauncherItem])?
    var iconProvider: ((LauncherItem) -> NSImage?)?
    var onFinish: ((LauncherItem?) -> Void)?
    private(set) var results: [LauncherItem] = []
    private(set) var selectedIndex = 0
    /// The live editor text, including text still being composed.
    var query: String { (field.currentEditor() as? NSTextView)?.string ?? field.stringValue }

    private let field = NSTextField(string: "")
    private let separator = NSBox()
    private let list = NSStackView()
    private var rows: [LauncherRowView] = []
    private var listHeight: NSLayoutConstraint?
    private var isPresenting = false
    private var topEdge: CGFloat = 0

    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: Self.headerHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        delegate = self
        guard let contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.cornerCurve = .continuous
        applyAppearance()
        field.font = .systemFont(ofSize: 24)
        field.placeholderString = "Application or Settings pane"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        // Focus changes must not submit; only an explicit Return command does that.
        field.cell?.sendsActionOnEndEditing = false
        field.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(field)
        separator.boxType = .separator
        separator.isHidden = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(list)
        for index in 0..<Self.maxResults {
            let row = LauncherRowView()
            row.isHidden = true
            row.onClick = { [weak self] in self?.choose(index) }
            row.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.listInset).isActive = true
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            rows.append(row)
            list.addArrangedSubview(row)
        }
        let listHeight = list.heightAnchor.constraint(equalToConstant: 0)
        self.listHeight = listHeight
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.headerHeight / 2),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.headerHeight),
            list.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Self.listSpacing),
            list.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.listInset),
            listHeight,
        ])
    }

    func show() {
        field.stringValue = ""
        results = []
        selectedIndex = 0
        isPresenting = true
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let screen {
            // The top edge stays put while rows appear, so the field never jumps.
            topEdge = screen.visibleFrame.midY + 180
            setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - Self.width / 2, y: topEdge - frame.height))
        }
        applyAppearance()
        reloadResults()
        // A global hotkey shows the panel while another app stays active; a
        // nonactivating panel takes keyboard focus without an activation race.
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func hide() {
        isPresenting = false
        orderOut(nil)
    }

    /// Re-ranks the current query, keeping the selection when the list only grew.
    func reloadResults() {
        results = Array((resultsProvider?(query) ?? []).prefix(Self.maxResults))
        selectedIndex = min(selectedIndex, max(0, results.count - 1))
        for (index, row) in rows.enumerated() {
            if index < results.count {
                let item = results[index]
                row.configure(item, icon: iconProvider?(item), selected: index == selectedIndex)
                row.isHidden = false
            } else {
                row.isHidden = true
            }
        }
        separator.isHidden = results.isEmpty
        let listHeight = CGFloat(results.count) * Self.rowHeight
        self.listHeight?.constant = listHeight
        let height = Self.headerHeight + (results.isEmpty ? 0 : 1 + Self.listSpacing + listHeight + Self.listInset)
        setFrame(CGRect(x: frame.minX, y: topEdge - height, width: Self.width, height: height), display: true)
    }

    func windowDidResignKey(_ notification: Notification) { finish(nil) }

    func controlTextDidChange(_ obj: Notification) {
        selectedIndex = 0
        reloadResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if results.indices.contains(selectedIndex) { finish(results[selectedIndex]) }
            return true // Nothing to open yet; the panel stays open.
        case #selector(NSResponder.cancelOperation(_:)):
            finish(nil)
            return true
        case #selector(NSResponder.moveDown(_:)):
            select(selectedIndex + 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            select(selectedIndex - 1)
            return true
        default:
            return false
        }
    }

    private func select(_ index: Int) {
        guard !results.isEmpty else { return }
        let clamped = min(max(index, 0), results.count - 1)
        guard clamped != selectedIndex else { return }
        rows[selectedIndex].setSelected(false)
        selectedIndex = clamped
        rows[selectedIndex].setSelected(true)
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        select(index)
        finish(results[index])
    }

    private func finish(_ item: LauncherItem?) {
        guard isPresenting else { return }
        isPresenting = false
        onFinish?(item)
    }

    private func applyAppearance() {
        guard let layer = contentView?.layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

/// One result: icon, name, and the kind of item. Clicks choose it without taking focus.
@MainActor
final class LauncherRowView: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private var selected = false

    override var acceptsFirstResponder: Bool { false }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        caption.font = .systemFont(ofSize: 11)
        for view in [icon, title, caption] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            caption.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            caption.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 0),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func configure(_ item: LauncherItem, icon image: NSImage?, selected: Bool) {
        icon.image = image
        title.stringValue = item.name
        caption.stringValue = item.kind == .application ? "Application" : "System Settings"
        setSelected(selected)
    }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        title.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        caption.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard selected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
