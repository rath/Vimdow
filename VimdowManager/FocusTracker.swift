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

struct FocusUpdate: Sendable {
    struct Reasons: OptionSet, Sendable {
        let rawValue: Int
        static let accessibility = Self(rawValue: 1 << 0)
        static let initial = Self(rawValue: 1 << 1)
        static let application = Self(rawValue: 1 << 2)
        static let space = Self(rawValue: 1 << 3)
        static let screens = Self(rawValue: 1 << 4)

        var forcesPlacement: Bool { !intersection([.initial, .application, .space, .screens]).isEmpty }
    }

    let target: FocusTarget
    var windows: [ScreenWindow] = []
    var reasons: Reasons = []
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
        var fallback: CGWindowID?
        for window in windows where window.pid == pid && window.layer == 0 && window.alpha > 0 {
            if matches(window.bounds, frame) { return window.id }
            if fallback == nil { fallback = window.id }
        }
        return fallback
    }

    /// The topmost visible normal-level window of another app among the windows above the
    /// focused one. Vimdow's own windows, the dim sheets included, never count.
    static func blockingWindow(above id: CGWindowID, in windows: [ScreenWindow],
                               focusedPID: pid_t, ownPID: pid_t) -> CGWindowID? {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return nil }
        return windows[..<index].first {
            $0.layer == 0 && $0.alpha > 0 && $0.pid != focusedPID && $0.pid != ownPID
        }?.id
    }

    /// Only skip ordering when all sheets form a contiguous block beside the anchor.
    /// Missing sheets (including those on another Space) are not evidence of correct placement.
    static func sheetsAreOrdered(_ sheets: Set<CGWindowID>, beside anchor: CGWindowID,
                                 above: Bool, in windows: [ScreenWindow]) -> Bool {
        guard !sheets.isEmpty else { return true }
        let ids = windows.filter { $0.layer == 0 && ($0.alpha > 0 || sheets.contains($0.id)) }.map(\.id)
        guard let index = ids.firstIndex(of: anchor) else { return false }
        let start = above ? index - sheets.count : index + 1
        guard start >= 0, start + sheets.count <= ids.count else { return false }
        return Set(ids[start..<(start + sheets.count)]) == sheets
    }
}

/// System reads are injectable so failure handling and the IPC budget can be tested without AX permission.
@MainActor
struct FocusReader {
    var isTrusted: () -> Bool = { AXIsProcessTrusted() }
    var frontmostPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var attribute: (AXUIElement, String) -> CFTypeRef? = { element, name in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    var attributes: (AXUIElement, [String]) -> (AXError, [Any]?) = { element, names in
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
        return (result, values as? [Any])
    }
    var windows: () -> [ScreenWindow] = {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return FocusResolution.screenWindows(raw)
    }

    func resolve(ownPID: pid_t, reasons: FocusUpdate.Reasons) -> (FocusUpdate, AXUIElement?) {
        func update(_ target: FocusTarget, windows: [ScreenWindow] = []) -> FocusUpdate {
            FocusUpdate(target: target, windows: windows, reasons: reasons)
        }
        guard isTrusted() else { return (update(.unavailable), nil) }
        guard let pid = frontmostPID() else { return (update(.none), nil) }
        guard pid != ownPID else { return (update(.ownApp), nil) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused = attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (update(.none), nil) }
        let window = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)
        let names = [kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"]
        let (status, batch) = attributes(window, names)
        let values: [Any]
        switch status {
        case .success:
            guard let batch, batch.count == names.count else { return (update(.none), window) }
            values = batch
        case .notImplemented:
            values = names.map { attribute(window, $0) ?? kCFNull! }
        default:
            // Do not multiply timeouts or retry a window that disappeared during the read.
            return (update(.none), window)
        }
        guard (values[0] as? Bool) != true,
              let frame = Self.frame(position: values[1], size: values[2]) else { return (update(.none), window) }
        let isFullScreen = (values[3] as? Bool) == true
        let snapshot = windows()
        guard let id = FocusResolution.windowID(for: pid, frame: frame, in: snapshot) else {
            return (update(.none, windows: snapshot), window)
        }
        return (update(.window(id: id, pid: pid, frame: frame, isFullScreen: isFullScreen), windows: snapshot), window)
    }

    private static func frame(position: Any, size: Any) -> CGRect? {
        guard CFGetTypeID(position as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(size as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

/// Follows the focused window through workspace and Accessibility notifications.
/// Owns the AX observer and elements; only snapshots of values leave.
@MainActor
final class FocusTracker: NSObject {
    /// Called after every resolve, whether or not the target changed; placement is idempotent.
    var onUpdate: ((FocusUpdate) -> Void)?
    private(set) var target: FocusTarget = .unavailable
    private(set) var isRunning = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private let reader: FocusReader
    private var pendingReasons: FocusUpdate.Reasons = []
    private var refreshTask: Task<Void, Never>?
    private var generation = 0

    init(reader: FocusReader = FocusReader()) {
        self.reader = reader
        super.init()
    }

    private static let applicationNotifications = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    func start() {
        guard !isRunning else { return }
        generation += 1
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        attach(to: reader.frontmostPID())
        update(reasons: .initial)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
        pendingReasons = []
        target = .unavailable
    }

    /// Coalesces notifications until the queued main-actor task runs, retaining every cause.
    func refresh(reason: FocusUpdate.Reasons = .accessibility) {
        guard isRunning else { return }
        pendingReasons.formUnion(reason)
        guard refreshTask == nil else { return }
        let current = generation
        refreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, isRunning, generation == current else { return }
            refreshTask = nil
            let reasons = pendingReasons
            pendingReasons = []
            update(reasons: reasons)
        }
    }

    @objc private func applicationActivated(_ notification: Notification) {
        let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        attach(to: (activated ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier)
        refresh(reason: .application)
    }

    @objc private func spaceChanged() { refresh(reason: .space) }

    private func update(reasons: FocusUpdate.Reasons) {
        guard isRunning else { return }
        let (resolved, window) = reader.resolve(ownPID: ownPID, reasons: reasons)
        observeDestruction(of: window)
        target = resolved.target
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
}
