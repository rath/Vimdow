import Foundation
import CoreGraphics

public enum WindowGeometry {
    public static func apply(
        _ direction: Direction, to frame: CGRect, count: Int = 1,
        anchor: ResizeAnchor? = nil, step: Int = 20
    ) -> CGRect {
        let distance = CGFloat(max(1, step)) * CGFloat(max(1, count))
        let dx: CGFloat = direction == .left ? -distance : direction == .right ? distance : 0
        let dy: CGFloat = direction == .up ? -distance : direction == .down ? distance : 0
        guard let anchor else { return frame.offsetBy(dx: dx, dy: dy) }
        switch anchor {
        case .topLeft:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: max(1, frame.width + dx), height: max(1, frame.height + dy))
        case .bottomRight:
            let width = max(1, frame.width - dx)
            let height = max(1, frame.height - dy)
            return CGRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height)
        }
    }

    public static func transfer(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let width = min(frame.width, target.width)
        let height = min(frame.height, target.height)
        return CGRect(x: min(max(target.minX + frame.minX - source.minX, target.minX), target.maxX - width),
                      y: min(max(target.minY + frame.minY - source.minY, target.minY), target.maxY - height),
                      width: width, height: height)
    }

    public static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        // A window can straddle displays or have its top-left corner off screen.
        // Prefer the display containing most of it, then the nearest display.
        func area(_ screen: CGRect) -> CGFloat {
            let overlap = screen.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        func distance(_ screen: CGRect) -> CGFloat {
            let dx = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
            let dy = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
            return dx * dx + dy * dy
        }
        return screens.indices.max { lhs, rhs in
            let left = area(screens[lhs]), right = area(screens[rhs])
            return left == right ? distance(screens[lhs]) > distance(screens[rhs]) : left < right
        }
    }

    /// AX/Quartz uses a top-left origin; AppKit uses the primary display's bottom-left origin.
    public static func appKitFrame(from frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

public enum WindowSelection {
    public static func index(
        in windows: [WindowInfo], current: UUID?, step: Int, count: Int = 1, query: String? = nil
    ) -> Int? {
        guard !windows.isEmpty, step != 0 else { return nil }
        let direction = step < 0 ? -1 : 1
        let start = windows.firstIndex(where: { $0.id == current })
        let repetitions = max(1, count)
        guard let query else {
            guard let start else { return direction > 0 ? 0 : windows.count - 1 }
            let distance = min(repetitions, windows.count)
            return min(windows.count - 1, max(0, start + direction * distance))
        }
        let origin = start ?? (direction > 0 ? windows.count - 1 : 0)
        let matches = (1...windows.count).compactMap { offset -> Int? in
            let index = (origin + direction * offset + windows.count) % windows.count
            return windows[index].name.range(of: query, options: .caseInsensitive) != nil ? index : nil
        }
        guard !matches.isEmpty else { return nil }
        return matches[(repetitions - 1) % matches.count]
    }

    public static func nextPage(after offset: Int?, count: Int) -> Int {
        guard let offset, offset + 9 < count else { return 0 }
        return offset + 9
    }
}
