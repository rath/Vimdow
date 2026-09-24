import Foundation
import CoreGraphics

public enum Mode: Equatable, Sendable {
    case normal, command, quickSwitch, search
}

public enum Direction: CaseIterable, Sendable {
    case left, down, up, right
}

public enum ResizeAnchor: Sendable {
    case topLeft, bottomRight
}

public enum Command: Sendable {
    case enter, escape, digit(Int), move(Direction), resize(Direction, ResizeAnchor)
    case cycle(Int), quickSwitch, search, repeatSearch(Int), nextScreen, quit
}

public struct RepeatPrefix: Sendable {
    public private(set) var value: Int?

    public init() {}

    public mutating func append(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        let (shifted, overflow) = (value ?? 0).multipliedReportingOverflow(by: 10)
        let (next, additionOverflow) = shifted.addingReportingOverflow(digit)
        guard !overflow, !additionOverflow else { return }
        value = next
    }

    public mutating func take() -> Int {
        defer { value = nil }
        return max(1, value ?? 1)
    }

    public mutating func reset() { value = nil }
}

public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let frame: CGRect
    public let isFocused: Bool

    public init(id: UUID, name: String, frame: CGRect, isFocused: Bool = false) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isFocused = isFocused
    }
}

public enum WindowFailure: Error, Equatable, LocalizedError {
    case permissionDenied, noFocusedWindow, unavailableWindow, unsupportedOperation
    case accessibility(Int32)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Allow Vimdow in System Settings → Privacy & Security → Accessibility."
        case .noFocusedWindow: "There is no focused window to control."
        case .unavailableWindow: "The window is no longer available."
        case .unsupportedOperation: "This window does not support the requested operation."
        case .accessibility(let code): "The application could not respond to the window operation (AX error \(code))."
        }
    }
}

@MainActor
public protocol WindowControlling: AnyObject {
    func windows() throws -> [WindowInfo]
    func focusedWindow() throws -> WindowInfo
    func focus(_ id: UUID, movePointer: Bool) throws
    func setFrame(_ frame: CGRect, of id: UUID) throws
    func screenFrames() -> [CGRect]
}

@MainActor
public protocol CommandPresenting: AnyObject {
    func setMode(_ mode: Mode)
    func showGuides(_ windows: [WindowInfo])
    func hideGuides()
    func showSearch()
    func hideSearch()
    func showFailure(_ error: any Error)
    func quit()
}
