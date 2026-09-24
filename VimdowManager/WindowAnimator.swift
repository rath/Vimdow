import AppKit
import VimdowCore

/// Glides windows toward their destinations in step with the display refresh.
@MainActor
final class WindowAnimator: NSObject {
    /// Applies one frame to a window. `previous` is the frame applied before it,
    /// and `isFinal` marks the destination, which must be applied in full.
    typealias Apply = @MainActor (_ id: UUID, _ frame: CGRect, _ previous: CGRect, _ isFinal: Bool) throws -> Void

    /// Reports a failure after a glide has stopped; the window stays where it was.
    var onFailure: ((any Error) -> Void)?
    private let apply: Apply
    private var motions: [UUID: FrameMotion] = [:]
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    init(apply: @escaping Apply) {
        self.apply = apply
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(finishAll),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Where a gliding window is heading; nil when it is at rest.
    func destination(of id: UUID) -> CGRect? { motions[id]?.target }

    /// The frame most recently applied to a gliding window.
    func presentedFrame(of id: UUID) -> CGRect? { motions[id]?.frame }

    func glide(_ id: UUID, from frame: CGRect, to target: CGRect) throws {
        if var motion = motions[id] {
            motion.retarget(target)
            motions[id] = motion
        } else if frame != target {
            // Held keys repeat about once per smoothing time, so their steps blend together.
            let smoothTime = min(max(NSEvent.keyRepeatInterval, 1.0 / 30), 0.1)
            motions[id] = FrameMotion(from: frame, to: target, smoothTime: smoothTime)
        }
        // A link can stop firing, for example when its display goes to sleep.
        guard motions[id] != nil, link == nil || CACurrentMediaTime() - lastTimestamp > 0.25 else { return }
        if !startLink(near: frame) {
            motions[id] = nil
            try apply(id, target, frame, true)
        }
    }

    func cancel(_ id: UUID) {
        motions[id] = nil
        if motions.isEmpty { stopLink() }
    }

    /// Moves every gliding window straight to its destination.
    @objc func finishAll() {
        let pending = motions
        motions.removeAll()
        stopLink()
        // A window that closed mid-glide has nothing left to finish.
        for (id, motion) in pending { try? apply(id, motion.target, motion.frame, true) }
    }

    private func startLink(near frame: CGRect) -> Bool {
        link?.invalidate()
        link = nil
        let screens = NSScreen.screens
        guard let primary = screens.first else { return false }
        let bounds = screens.map { WindowGeometry.quartzFrame(from: $0.frame, primaryHeight: primary.frame.height) }
        let screen = screens[WindowGeometry.screenIndex(for: frame, screens: bounds) ?? 0]
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = CACurrentMediaTime()
        return true
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - lastTimestamp
        lastTimestamp = link.targetTimestamp
        var failure: (any Error)?
        for (id, var motion) in motions {
            let previous = motion.frame
            let frame = motion.advance(by: elapsed)
            motions[id] = motion.isFinished ? nil : motion
            guard frame != previous || motion.isFinished else { continue }
            do {
                try apply(id, frame, previous, motion.isFinished)
            } catch {
                motions[id] = nil
                failure = failure ?? error
            }
        }
        if motions.isEmpty { stopLink() }
        // Report last: an alert runs a modal loop that can fire this link again.
        if let failure { onFailure?(failure) }
    }
}
