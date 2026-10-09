import AppKit

/// Owns the focus tracker and the sheets; the only dimming object the app delegate talks to.
@MainActor
final class DimController: NSObject {
    /// Vimdow's own window to keep bright while Vimdow is frontmost, such as a visible Settings window.
    var ownWindowNumber: @MainActor () -> Int? = { nil }
    private(set) var isEnabled = false
    private let tracker = FocusTracker()
    private let overlay = DimOverlay()

    /// Black alpha in percent; applies at once to visible sheets.
    var intensity: Int {
        get { overlay.intensity }
        set { overlay.intensity = newValue }
    }

    override init() {
        super.init()
        tracker.onUpdate = { [weak self] target in self?.apply(target) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func setEnabled(_ enabled: Bool, animated: Bool = true) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            overlay.show(animated: animated)
            tracker.start() // Publishes the current target, which places the sheets.
        } else {
            tracker.stop()
            overlay.hide(animated: animated)
        }
    }

    func stop() { setEnabled(false, animated: false) }

    @objc private func screensChanged() {
        overlay.rebuildScreens()
        if isEnabled { tracker.refresh() }
    }

    private func apply(_ target: FocusTarget) {
        overlay.place(target, ownWindowNumber: ownWindowNumber())
    }
}
