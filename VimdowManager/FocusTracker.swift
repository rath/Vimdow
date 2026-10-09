import AppKit
import ApplicationServices
import VimdowCore

/// What the dim sheets must leave bright. A value: no AX object escapes the tracker.
enum FocusTarget: Equatable, Sendable {
    /// `frame` is in Quartz coordinates, as Accessibility and the window list report it.
    case window(id: CGWindowID, pid: pid_t, frame: CGRect, isFullScreen: Bool)
    /// The frontmost app has no focused window, so everything is dimmed.
    case none
    /// Vimdow itself is frontmost; the caller decides which of its windows stays bright.
    case ownApp
    /// Accessibility is not trusted, so nothing can be resolved.
    case unavailable
}

/// A window as the window server lists it, front to back.
struct ScreenWindow: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let alpha: Double
    let bounds: CGRect
}

/// Pure matching rules over window-list values, so tests cover them without Accessibility.
enum FocusResolution {
    static func screenWindows(_ raw: [[String: Any]]) -> [ScreenWindow] {
        raw.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? Int, number > 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ScreenWindow(id: CGWindowID(number), pid: pid,
                                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1, bounds: frame)
        }
    }

    /// Accessibility and the window server can disagree by a point or two on scaled displays.
    static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance
    }

    /// The topmost visible normal-level window of `pid` whose bounds match `frame`, else that
    /// app's topmost one. Equal bounds resolve to the frontmost entry, which is the focused one.
    static func windowID(for pid: pid_t, frame: CGRect, in windows: [ScreenWindow]) -> CGWindowID? {
        let candidates = windows.filter { $0.pid == pid && $0.layer == 0 && $0.alpha > 0 }
        return (candidates.first { matches($0.bounds, frame) } ?? candidates.first)?.id
    }

    /// The topmost visible normal-level window of another app among the windows above the
    /// focused one. Vimdow's own windows, the dim sheets included, never count.
    static func blockingWindow(in above: [ScreenWindow], focusedPID: pid_t, ownPID: pid_t) -> CGWindowID? {
        above.first { $0.layer == 0 && $0.alpha > 0 && $0.pid != focusedPID && $0.pid != ownPID }?.id
    }
}

/// Follows the focused window through workspace and Accessibility notifications.
/// Owns the AX observer and elements; only `FocusTarget` values leave.
@MainActor
final class FocusTracker: NSObject {
    /// Called after every resolve, whether or not the target changed; placement is idempotent.
    var onUpdate: ((FocusTarget) -> Void)?
    private(set) var target: FocusTarget = .unavailable
    private(set) var isRunning = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private var pending = false

    private static let applicationNotifications = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        attach(to: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        update()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
        pending = false
        target = .unavailable
    }

    /// Re-resolves at most once per run-loop turn, however many notifications arrive.
    func refresh() {
        guard isRunning, !pending else { return }
        pending = true
        Task { @MainActor [weak self] in
            guard let self, pending else { return }
            pending = false
            update()
        }
    }

    @objc private func applicationActivated(_ notification: Notification) {
        let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        attach(to: (activated ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier)
        refresh()
    }

    @objc private func spaceChanged() { refresh() }

    private func update() {
        guard isRunning else { return }
        let (resolved, window) = Self.resolve(ownPID: ownPID)
        observeDestruction(of: window)
        target = resolved
        onUpdate?(resolved)
    }

    private func attach(to pid: pid_t?) {
        guard let pid, pid != ownPID else { detach(); return }
        guard pid != observedPID else { return }
        detach()
        guard AXIsProcessTrusted() else { return }
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            // The observer's source is scheduled on the main run loop.
            MainActor.assumeIsolated { tracker.refresh() }
        }, &created)
        guard status == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.applicationNotifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedApp = app
        observedPID = pid
    }

    private func detach() {
        if let observer {
            if let observedApp {
                for name in Self.applicationNotifications {
                    AXObserverRemoveNotification(observer, observedApp, name as CFString)
                }
            }
            if let observedWindow {
                AXObserverRemoveNotification(observer, observedWindow, kAXUIElementDestroyedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedApp = nil
        observedWindow = nil
        observedPID = nil
    }

    /// A closed focused window sends no focus change when its app keeps running without
    /// windows, so its destruction is observed directly. On the app element this
    /// notification fires for every destroyed element, far too often.
    private func observeDestruction(of window: AXUIElement?) {
        guard let observer else { observedWindow = nil; return }
        if let observedWindow, let window, CFEqual(observedWindow, window) { return }
        if let observedWindow {
            AXObserverRemoveNotification(observer, observedWindow, kAXUIElementDestroyedNotification as CFString)
        }
        observedWindow = nil
        guard let window else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon) == .success {
            observedWindow = window
        }
    }

    /// Frontmost app → focused AX window → its frame → the window server's number for it.
    private static func resolve(ownPID: pid_t) -> (FocusTarget, AXUIElement?) {
        guard AXIsProcessTrusted() else { return (.unavailable, nil) }
        guard let running = NSWorkspace.shared.frontmostApplication else { return (.none, nil) }
        let pid = running.processIdentifier
        guard pid != ownPID else { return (.ownApp, nil) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused = attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (.none, nil) }
        let window = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)
        guard (attribute(window, kAXMinimizedAttribute) as? Bool) != true,
              let frame = frame(of: window) else { return (.none, window) }
        let isFullScreen = (attribute(window, "AXFullScreen") as? Bool) == true
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let id = FocusResolution.windowID(for: pid, frame: frame, in: FocusResolution.screenWindows(raw)) else {
            return (.none, window)
        }
        return (.window(id: id, pid: pid, frame: frame, isFullScreen: isFullScreen), window)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
