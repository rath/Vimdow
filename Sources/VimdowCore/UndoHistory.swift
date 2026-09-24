import Foundation
import CoreGraphics

/// Frames that undo and redo restore, kept separately for each window.
///
/// Each entry holds the frame on the far side of one change. Travelling in
/// either direction leaves the current frame behind, so undoing and then
/// redoing returns a window to where it was, even after an app or the user
/// moved it by other means.
struct UndoHistory: Sendable {
    enum Travel: Sendable { case undo, redo }

    struct Entry: Equatable, Sendable {
        let frame: CGRect
        /// False when the change must not glide, as with display moves.
        let canGlide: Bool
    }

    private struct Stacks: Sendable {
        var undo: [Entry] = []
        var redo: [Entry] = []
    }

    /// The most changes kept for each window.
    let depth: Int
    /// The most windows kept; the least recently used window is forgotten first.
    let windowLimit: Int
    private var stacks: [UUID: Stacks] = [:]
    private var recent: [UUID] = []

    init(depth: Int = 100, windowLimit: Int = 50) {
        self.depth = max(1, depth)
        self.windowLimit = max(1, windowLimit)
    }

    /// Records the frame a window had before a change and clears its redo history.
    mutating func record(_ frame: CGRect, canGlide: Bool, for id: UUID) {
        var window = stacks[id] ?? Stacks()
        window.undo.append(Entry(frame: frame, canGlide: canGlide))
        window.undo.removeFirst(max(0, window.undo.count - depth))
        window.redo.removeAll()
        stacks[id] = window
        use(id)
    }

    /// Passes up to `count` changes, leaving `current` to travel back to. Returns
    /// the frame to apply, which may glide only if every change passed may glide,
    /// or nil when there is nothing to restore.
    mutating func travel(_ travel: Travel, count: Int, for id: UUID, from current: CGRect) -> Entry? {
        guard var window = stacks[id] else { return nil }
        let target = switch travel {
        case .undo: Self.pass(count, from: &window.undo, to: &window.redo, leaving: current)
        case .redo: Self.pass(count, from: &window.redo, to: &window.undo, leaving: current)
        }
        guard let target else { return nil }
        stacks[id] = window
        use(id)
        return target
    }

    /// Moves up to `count` entries from `source` to `destination`, replacing each
    /// with the frame it leaves behind, and returns the last frame reached.
    private static func pass(_ count: Int, from source: inout [Entry], to destination: inout [Entry],
                             leaving current: CGRect) -> Entry? {
        var frame = current
        var canGlide = true
        var passed = 0
        while passed < max(1, count), let entry = source.popLast() {
            destination.append(Entry(frame: frame, canGlide: entry.canGlide))
            frame = entry.frame
            canGlide = canGlide && entry.canGlide
            passed += 1
        }
        return passed > 0 ? Entry(frame: frame, canGlide: canGlide) : nil
    }

    private mutating func use(_ id: UUID) {
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > windowLimit { stacks[recent.removeFirst()] = nil }
    }
}
