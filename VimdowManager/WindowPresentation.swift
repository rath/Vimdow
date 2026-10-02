import AppKit
import CoreText
import QuartzCore
import VimdowCore

/// Brief, click-through pulses inside the newly focused window's bounds.
@MainActor
final class FocusFlash: NSPanel {
    private var dismissal: Task<Void, Never>?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let surface = NSView()
        surface.wantsLayer = true
        surface.setAccessibilityElement(false)
        contentView = surface
    }

    func show(_ quartzFrame: CGRect) {
        hide()
        guard let primary = NSScreen.screens.first,
              quartzFrame.width > 8, quartzFrame.height > 8,
              let layer = contentView?.layer else { return }
        let target = WindowGeometry.appKitFrame(from: quartzFrame, primaryHeight: primary.frame.height)
        setFrame(target.insetBy(dx: 2, dy: 2), display: false)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = 8
        layer.borderWidth = 3
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(reducedMotion ? 0 : 0.08).cgColor
        }
        layer.opacity = 0
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        // Two distinct pulses; Reduce Motion uses one gentle outline fade.
        fade.duration = reducedMotion ? 0.36 : 0.18
        fade.repeatCount = reducedMotion ? 1 : 2
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "focusFlash")
        orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        orderOut(nil)
        contentView?.layer?.removeAllAnimations()
    }
}

/// A brief confirmation that never becomes a keyboard or mouse target.
@MainActor
final class StatusNotice: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var dismissal: Task<Void, Never>?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 8
        contentView = surface
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        surface.addSubview(label)
    }

    func show(_ text: String, near quartzFrame: CGRect?) {
        dismissal?.cancel()
        guard let primary = NSScreen.screens.first else { return }
        let target = quartzFrame.map { WindowGeometry.appKitFrame(from: $0, primaryHeight: primary.frame.height) }
        let screen = target.flatMap { target in
            NSScreen.screens.max { lhs, rhs in
                let a = lhs.frame.intersection(target), b = rhs.frame.intersection(target)
                return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
            }
        } ?? NSScreen.main ?? primary
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: min(label.frame.width + 32, bounds.width), height: 44)
        let anchor = target ?? bounds
        let x = min(max(anchor.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let y = min(max(anchor.maxY - size.height - 12, bounds.minY), bounds.maxY - size.height)
        setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        label.frame = CGRect(x: 16, y: (size.height - label.frame.height) / 2,
                             width: size.width - 32, height: label.frame.height)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        orderFrontRegardless()
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        orderOut(nil)
    }
}

/// AppKit-coordinate layout, independent of live windows and display scale.
enum GuideLayout {
    static let side: CGFloat = 160
    static let gap: CGFloat = 12

    static func frames(for targets: [CGRect], screens: [CGRect]) -> [CGRect] {
        var result = targets.map { CGRect(x: $0.midX - side / 2, y: $0.midY - side / 2,
                                          width: side, height: side) }
        let assignments = targets.map { WindowGeometry.screenIndex(for: $0, screens: screens) }
        for (screenIndex, screen) in screens.enumerated() {
            var groups = targets.indices.filter { assignments[$0] == screenIndex }.map { [$0] }
            // Each pass merges at least two groups, so this terminates in at most n passes.
            while !groups.isEmpty {
                for group in groups {
                    let center = CGPoint(x: group.reduce(0) { $0 + targets[$1].midX } / CGFloat(group.count),
                                         y: group.reduce(0) { $0 + targets[$1].midY } / CGFloat(group.count))
                    let frames = grid(count: group.count, center: center, screen: screen)
                    for (index, frame) in zip(group, frames) { result[index] = frame }
                }
                var collision: (Int, Int)?
                for a in groups.indices {
                    for b in groups.indices where b > a {
                        if groups[a].contains(where: { i in groups[b].contains(where: { j in
                            let overlap = result[i].insetBy(dx: -gap / 2, dy: -gap / 2)
                                .intersection(result[j].insetBy(dx: -gap / 2, dy: -gap / 2))
                            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
                        }) }) {
                            collision = (a, b)
                            break
                        }
                    }
                    if collision != nil { break }
                }
                guard let (a, b) = collision else { break }
                groups[a] = (groups[a] + groups[b]).sorted()
                groups.remove(at: b)
            }
        }
        return result
    }

    private static func grid(count: Int, center: CGPoint, screen: CGRect) -> [CGRect] {
        func size(columns: Int) -> CGSize {
            let rows = (count + columns - 1) / columns
            return CGSize(width: CGFloat(columns) * (side + gap) - gap,
                          height: CGFloat(rows) * (side + gap) - gap)
        }
        func overflow(_ size: CGSize) -> CGFloat {
            max(0, size.width - screen.width) + max(0, size.height - screen.height)
        }
        let columns = (1...count).min { a, b in
            let lhs = size(columns: a), rhs = size(columns: b)
            if overflow(lhs) != overflow(rhs) { return overflow(lhs) < overflow(rhs) }
            let leftShape = abs(lhs.width - lhs.height), rightShape = abs(rhs.width - rhs.height)
            return leftShape == rightShape ? a > b : leftShape < rightShape
        } ?? 1
        let extent = size(columns: columns)
        func origin(_ center: CGFloat, _ length: CGFloat, _ min: CGFloat, _ max: CGFloat) -> CGFloat {
            // An unusually small display still keeps the full-size badges centered.
            guard length <= max - min else { return (min + max - length) / 2 }
            return Swift.min(Swift.max(center - length / 2, min), max - length)
        }
        let x = origin(center.x, extent.width, screen.minX, screen.maxX)
        let y = origin(center.y, extent.height, screen.minY, screen.maxY)
        return (0..<count).map { index in
            CGRect(x: x + CGFloat(index % columns) * (side + gap),
                   y: y + extent.height - side - CGFloat(index / columns) * (side + gap),
                   width: side, height: side)
        }
    }
}

@MainActor
final class GuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GuideBadgeView: NSView {
    private let number: String

    init(number: Int) {
        self.number = String(number)
        super.init(frame: CGRect(x: 0, y: 0, width: GuideLayout.side, height: GuideLayout.side))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(self.number)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let text = NSAttributedString(string: number, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(text)
        // Center the visible glyph, without the font's unused ascender/descender space.
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

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
        let frames = GuideLayout.frames(for: targets.map {
            WindowGeometry.appKitFrame(from: $0.frame, primaryHeight: primary.frame.height)
        }, screens: NSScreen.screens.map(\.visibleFrame))
        for (index, frame) in frames.enumerated() {
            let panel = GuidePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = GuideBadgeView(number: index + 1)
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
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
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
        // Focus changes can end field editing while the panel is being activated.
        // They must not submit a search; only an explicit Return command does that.
        field.cell?.sendsActionOnEndEditing = false
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
        // A global hotkey can show the panel while another app remains active.
        // A nonactivating panel takes keyboard focus without an activation race.
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func hide() {
        isSearching = false
        orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { finish(nil) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finish(textView.string)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(nil)
            return true
        default:
            return false
        }
    }

    private func finish(_ query: String?) {
        guard isSearching else { return }
        isSearching = false
        onFinish?(query)
    }
}
