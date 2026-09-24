import Foundation

public enum DisplayMoveBehavior: String, CaseIterable, Sendable {
    case fillDisplay, keepSize
}

public struct WindowPreferences: Equatable, Sendable {
    public let moveStep: Int
    public let resizeStep: Int
    public let displayBehavior: DisplayMoveBehavior
    public let resizeStopsAtDisplayEdges: Bool
    public let animatesSteps: Bool

    public init(moveStep: Int = 20, resizeStep: Int = 20,
                displayBehavior: DisplayMoveBehavior = .fillDisplay,
                resizeStopsAtDisplayEdges: Bool = true, animatesSteps: Bool = true) {
        self.moveStep = (1...200).contains(moveStep) ? moveStep : 20
        self.resizeStep = (1...200).contains(resizeStep) ? resizeStep : 20
        self.displayBehavior = displayBehavior
        self.resizeStopsAtDisplayEdges = resizeStopsAtDisplayEdges
        self.animatesSteps = animatesSteps
    }
}
