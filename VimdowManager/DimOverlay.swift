import AppKit
import VimdowCore

/// A translucent black sheet over one display. It is never key and never a click target.
@MainActor
final class DimWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Private AppKit hook that HazeOver uses too: without it, a dragged window no longer
    /// snaps to its neighbours' edges while a sheet lies between them. Inert if never consulted.
    @objc(_canBeSnappingTarget) var canBeSnappingTarget: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        level = .normal
        // Not fullScreenAuxiliary: a sheet must never land above a full-screen window.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        alphaValue = 0
        let surface = NSView()
        surface.setAccessibilityElement(false)
        contentView = surface
    }
}

/// One sheet per display, ordered just below the focused window so everything else looks
/// dimmed. The window server composites it; nothing is drawn or timed while focus rests.
@MainActor
final class DimOverlay {
    static let fadeDuration: TimeInterval = 0.15
    /// An activated app's windows are raised shortly after the activation notification;
    /// one re-placement after that raise settles the order.
    static let settleDelay: Duration = .milliseconds(150)

    private(set) var windows: [DimWindow] = []
    private(set) var isShowing = false
    /// Black alpha in percent.
    var intensity = 50 {
        didSet { if isShowing { for window in windows { window.alphaValue = alpha } } }
    }
    private var screenFrames: [CGRect] = [] // Quartz, parallel to `windows`.
    private var generation = 0
    private var settle: Task<Void, Never>?
    private var lastTarget: FocusTarget = .unavailable
    private var lastOwnWindowNumber: Int?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var alpha: CGFloat { CGFloat(intensity) / 100 }

    func show(animated: Bool) {
        generation += 1
        if windows.isEmpty { build() }
        isShowing = true
        fade(to: alpha, animated: animated)
    }

    func hide(animated: Bool) {
        generation += 1
        let current = generation
        isShowing = false
        settle?.cancel()
        settle = nil
        let duration = fade(to: 0, animated: animated)
        guard duration > 0 else { orderOutAll(); return }
        Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, generation == current else { return } // A newer show wins.
            orderOutAll()
        }
    }

    /// Orders the sheets for `target`. Pure z-order: nothing is redrawn.
    func place(_ target: FocusTarget, ownWindowNumber: Int?) {
        lastTarget = target
        lastOwnWindowNumber = ownWindowNumber
        settle?.cancel()
        settle = nil
        guard isShowing else { return }
        switch target {
        case .unavailable:
            orderOutAll()
        case .none:
            // Top of the normal level, still below Vimdow's floating and status-bar panels.
            for window in windows { window.orderFrontRegardless() }
        case .ownApp:
            if let ownWindowNumber {
                for window in windows { window.order(.below, relativeTo: ownWindowNumber) }
            } else {
                for window in windows { window.orderFrontRegardless() }
            }
        case .window(let id, let pid, let frame, let isFullScreen):
            // A full-screen window lives on its own Space; its display is left alone.
            let skipped = isFullScreen ? WindowGeometry.screenIndex(for: frame, screens: screenFrames) : nil
            // Just after activation another app's window can still sit above the focused
            // one; a sheet above it is lifted over by the pending raise, not left on top.
            let blocker = blockingWindow(above: id, focusedPID: pid)
            for (index, window) in windows.enumerated() {
                if index == skipped {
                    window.orderOut(nil)
                } else if let blocker {
                    window.order(.above, relativeTo: Int(blocker))
                } else {
                    window.order(.below, relativeTo: Int(id))
                }
            }
            settle = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: Self.settleDelay) } catch { return }
                guard let self, isShowing, lastTarget == target else { return }
                for (index, window) in windows.enumerated() where index != skipped {
                    window.order(.below, relativeTo: Int(id))
                }
            }
        }
    }

    /// Displays changed: rebuild the sheets to the new frames and restore the last placement.
    func rebuildScreens() {
        orderOutAll()
        windows = []
        screenFrames = []
        guard isShowing else { return }
        build()
        for window in windows { window.alphaValue = alpha }
        place(lastTarget, ownWindowNumber: lastOwnWindowNumber)
    }

    private func build() {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        windows = screens.map { DimWindow(frame: $0.frame) }
        screenFrames = screens.map { WindowGeometry.quartzFrame(from: $0.frame, primaryHeight: primary.frame.height) }
    }

    private func orderOutAll() {
        for window in windows { window.orderOut(nil) }
    }

    private func blockingWindow(above id: CGWindowID, focusedPID: pid_t) -> CGWindowID? {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], id)
            as? [[String: Any]] ?? []
        return FocusResolution.blockingWindow(in: FocusResolution.screenWindows(raw), focusedPID: focusedPID, ownPID: ownPID)
    }

    /// Returns how long the fade takes; 0 when the value was applied at once.
    @discardableResult
    private func fade(to value: CGFloat, animated: Bool) -> TimeInterval {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            for window in windows { window.alphaValue = value }
            return 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            for window in windows { window.animator().alphaValue = value }
        }
        return Self.fadeDuration
    }
}
