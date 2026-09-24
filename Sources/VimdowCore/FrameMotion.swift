import CoreGraphics
import Foundation

/// Glides a window frame toward a destination that further steps may keep moving.
///
/// Each edge follows a critically damped spring: a single step eases into place,
/// held keys blend into steady motion, and no edge passes its destination.
/// Edges move by whole points from the starting frame, so edges that stay put
/// remain exact and a moving window keeps its size.
public struct FrameMotion: Sendable {
    public private(set) var target: CGRect
    /// The frame most recently returned by `advance(by:)`.
    public private(set) var frame: CGRect
    private let start: CGRect
    private let smoothTime: CGFloat
    // Offsets from the starting edges, in points: left, top, right, bottom.
    private var offsets: [CGFloat] = [0, 0, 0, 0]
    private var velocities: [CGFloat] = [0, 0, 0, 0]

    /// `smoothTime` is about how long, in seconds, the frame trails a moving destination.
    public init(from frame: CGRect, to target: CGRect, smoothTime: TimeInterval) {
        start = frame
        self.frame = frame
        self.target = target
        self.smoothTime = CGFloat(max(smoothTime, 0.001))
    }

    public var isFinished: Bool { frame == target }

    public mutating func retarget(_ target: CGRect) {
        self.target = target
    }

    /// Returns the frame to show after `elapsed` seconds, ending exactly at `target`.
    public mutating func advance(by elapsed: TimeInterval) -> CGRect {
        // Deriving the right and bottom goals from size changes keeps them
        // identical to the left and top goals whenever the size is unchanged.
        let dx = target.minX - start.minX, dy = target.minY - start.minY
        let goals = [dx, dy, dx + (target.width - start.width), dy + (target.height - start.height)]
        for edge in goals.indices {
            Self.damp(&offsets[edge], &velocities[edge], toward: goals[edge],
                      smoothTime: smoothTime, elapsed: CGFloat(max(elapsed, 0)))
        }
        if zip(offsets, goals).allSatisfy({ abs($1 - $0) < 0.5 }) {
            frame = target
        } else {
            let points = offsets.map { $0.rounded() }
            frame = CGRect(x: start.minX + points[0], y: start.minY + points[1],
                           width: max(1, start.width + (points[2] - points[0])),
                           height: max(1, start.height + (points[3] - points[1])))
        }
        return frame
    }

    /// Critically damped smoothing (Game Programming Gems 4, section 1.10)
    /// that stops at the goal instead of passing it.
    private static func damp(_ value: inout CGFloat, _ velocity: inout CGFloat, toward goal: CGFloat,
                             smoothTime: CGFloat, elapsed: CGFloat) {
        let omega = 2 / smoothTime
        let x = omega * elapsed
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - goal
        let carried = (velocity + omega * change) * elapsed
        let next = goal + (change + carried) * decay
        velocity = (velocity - omega * carried) * decay
        if (next - goal) * (value - goal) <= 0 {
            value = goal
            velocity = 0
        } else {
            value = next
        }
    }
}
