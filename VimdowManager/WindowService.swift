import AppKit
import ApplicationServices
import VimdowCore

/// Owns AX references. No AX object escapes into the command model or the UI.
@MainActor
final class WindowService: WindowControlling {
    private struct Handle {
        let pid: pid_t
        let app: AXUIElement
        let window: AXUIElement
    }

    private var handles: [UUID: Handle] = [:]
    private lazy var animator = WindowAnimator { [unowned self] id, frame, previous, isFinal in
        try self.applyGlide(frame, previous: previous, isFinal: isFinal, of: id)
    }

    /// Reports failures of glides that continue after `setFrame` returns.
    var onGlideFailure: ((any Error) -> Void)? {
        get { animator.onFailure }
        set { animator.onFailure = newValue }
    }

    func windows() throws -> [WindowInfo] {
        try requirePermission()
        // Listing matches AX frames against on-screen bounds, so glides land first.
        animator.finishAll()
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        var visible: [pid_t: [CGRect]] = [:]
        for entry in raw {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            visible[pid, default: []].append(frame)
        }
        let focused = try? focusedWindow()
        var result: [(info: WindowInfo, pid: pid_t, index: Int)] = []
        var live: Set<UUID> = []
        for pid in visible.keys.sorted() {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard let elements = try? attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Application"
            for (index, element) in elements.enumerated() {
                AXUIElementSetMessagingTimeout(element, 0.25)
                guard let frame = try? frame(of: element), frame.width >= 50, frame.height >= 50,
                      visible[pid, default: []].contains(where: { matches($0, frame) }) else { continue }
                let id = remember(Handle(pid: pid, app: app, window: element))
                live.insert(id)
                result.append((WindowInfo(id: id, name: name, frame: frame, isFocused: focused?.id == id), pid, index))
            }
        }
        handles = handles.filter { live.contains($0.key) }
        // Permission may have been revoked during the scan. Never silently treat that as an empty desktop.
        try requirePermission()
        return result.sorted {
            if $0.info.frame.minX != $1.info.frame.minX { return $0.info.frame.minX < $1.info.frame.minX }
            if $0.pid != $1.pid { return $0.pid < $1.pid }
            return $0.index < $1.index
        }.map(\.info)
    }

    func focusedWindow() throws -> WindowInfo {
        try requirePermission()
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowFailure.noFocusedWindow
        }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let value: CFTypeRef
        do { value = try attribute(app, kAXFocusedWindowAttribute) }
        catch WindowFailure.accessibility(let code) where code == AXError.noValue.rawValue {
            throw WindowFailure.noFocusedWindow
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw WindowFailure.noFocusedWindow }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        let id = remember(Handle(pid: running.processIdentifier, app: app, window: element))
        // A gliding window reports its destination so that repeated steps add up.
        let bounds = try animator.destination(of: id) ?? frame(of: element)
        return WindowInfo(id: id, name: running.localizedName ?? "Application", frame: bounds, isFocused: true)
    }

    func focus(_ id: UUID, movePointer: Bool) throws {
        try requirePermission()
        let handle = try handle(for: id)
        let bounds = try animator.destination(of: id) ?? frame(of: handle.window)
        let mainResult = AXUIElementSetAttributeValue(handle.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if mainResult != .attributeUnsupported { try check(mainResult) }
        let raiseResult = AXUIElementPerformAction(handle.window, kAXRaiseAction as CFString)
        if raiseResult != .actionUnsupported { try check(raiseResult) }
        try check(AXUIElementSetAttributeValue(handle.app, kAXFrontmostAttribute as CFString, kCFBooleanTrue))
        if movePointer { CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY)) }
    }

    func setFrame(_ desired: CGRect, of id: UUID, animated: Bool) throws {
        try requirePermission()
        let element = try handle(for: id).window
        guard desired.minX.isFinite, desired.minY.isFinite, desired.width.isFinite, desired.height.isFinite,
              desired.width > 0, desired.height > 0 else { throw WindowFailure.unsupportedOperation }
        guard animated else {
            animator.cancel(id)
            try place(element, at: desired)
            return
        }
        let current = try animator.presentedFrame(of: id) ?? frame(of: element)
        if current.size != desired.size { try requireSettable(element, kAXSizeAttribute) }
        if current.origin != desired.origin { try requireSettable(element, kAXPositionAttribute) }
        try animator.glide(id, from: current, to: desired)
    }

    /// Applies one glide frame. Intermediate frames set only what changed, back to
    /// back, so that edges meant to stay put barely shift between the two calls.
    private func applyGlide(_ frame: CGRect, previous: CGRect, isFinal: Bool, of id: UUID) throws {
        guard let element = handles[id]?.window else { throw WindowFailure.unavailableWindow }
        if isFinal {
            try place(element, at: frame)
            return
        }
        if frame.origin != previous.origin { try setPosition(frame.origin, of: element) }
        if frame.size != previous.size { try setSize(frame.size, of: element) }
    }

    private func place(_ element: AXUIElement, at desired: CGRect) throws {
        let current = try frame(of: element)
        if current.size != desired.size { try requireSettable(element, kAXSizeAttribute) }
        if current.origin != desired.origin { try requireSettable(element, kAXPositionAttribute) }
        // Move before resizing: apps can constrain size to the current display.
        // Resizing on the smaller source display can otherwise prevent a window
        // from filling the larger destination display.
        if current.origin != desired.origin {
            try setPosition(desired.origin, of: element)
        }
        let moved = try frame(of: element)
        if moved.size != desired.size {
            try requireSettable(element, kAXSizeAttribute)
            try setSize(desired.size, of: element)
        }
        // Moving or resizing may adjust the origin to keep the old frame on
        // screen. Reapply the requested origin after the final size is in place.
        if try frame(of: element).origin != desired.origin {
            try requireSettable(element, kAXPositionAttribute)
            try setPosition(desired.origin, of: element)
        }
    }

    private func setPosition(_ origin: CGPoint, of element: AXUIElement) throws {
        var position = origin
        guard let value = AXValueCreate(.cgPoint, &position) else { throw WindowFailure.unsupportedOperation }
        try check(AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value))
    }

    private func setSize(_ size: CGSize, of element: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowFailure.unsupportedOperation }
        try check(AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value))
    }

    func screenFrames() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
    }

    func visibleScreenFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map {
            WindowGeometry.quartzFrame(from: $0.visibleFrame, primaryHeight: primary.frame.height)
        }
    }

    private func requirePermission() throws {
        guard AXIsProcessTrusted() else { throw WindowFailure.permissionDenied }
    }

    private func remember(_ handle: Handle) -> UUID {
        if let existing = handles.first(where: { $0.value.pid == handle.pid && CFEqual($0.value.window, handle.window) }) {
            return existing.key
        }
        let id = UUID()
        handles[id] = handle
        return id
    }

    private func handle(for id: UUID) throws -> Handle {
        guard let handle = handles[id], NSRunningApplication(processIdentifier: handle.pid) != nil else {
            throw WindowFailure.unavailableWindow
        }
        return handle
    }

    private func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, name as CFString, &value))
        guard let value else { throw WindowFailure.unavailableWindow }
        return value
    }

    private func frame(of element: AXUIElement) throws -> CGRect {
        let positionValue = try attribute(element, kAXPositionAttribute)
        let sizeValue = try attribute(element, kAXSizeAttribute)
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw WindowFailure.unsupportedOperation
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { throw WindowFailure.unsupportedOperation }
        return CGRect(origin: position, size: size)
    }

    private func requireSettable(_ element: AXUIElement, _ name: String) throws {
        var settable = DarwinBoolean(false)
        try check(AXUIElementIsAttributeSettable(element, name as CFString, &settable))
        guard settable.boolValue else { throw WindowFailure.unsupportedOperation }
    }

    private func check(_ error: AXError) throws {
        switch error {
        case .success: return
        case .apiDisabled: throw WindowFailure.permissionDenied
        case .invalidUIElement: throw WindowFailure.unavailableWindow
        case .attributeUnsupported, .actionUnsupported, .notImplemented: throw WindowFailure.unsupportedOperation
        default: throw WindowFailure.accessibility(error.rawValue)
        }
    }

    private func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1
            && abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }
}
