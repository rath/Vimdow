import AppKit
import OSLog
import VimdowCore

/// Owns the launcher panel, its catalog, and the learned history, and opens what the user picks.
@MainActor
final class LauncherController {
    /// Runs when the panel finishes, before anything is opened, so the coordinator can
    /// leave launcher mode and hide the panel first.
    var onFinish: (() -> Void)?
    private let panel = LauncherPanel()
    private let catalog = LauncherCatalog()
    private let store: SettingsStore
    private var history = LauncherHistory()
    private var icons: [String: NSImage] = [:]
    private lazy var settingsIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")
    private let logger = Logger(subsystem: "rath.toys.VimdowManager", category: "Launcher")

    init(store: SettingsStore) {
        self.store = store
        panel.resultsProvider = { [unowned self] query in
            LauncherMatcher.rank(catalog.items, query: query, history: history)
        }
        panel.iconProvider = { [unowned self] item in icon(for: item) }
        catalog.onChange = { [weak self] in self?.panel.reloadResults() }
        panel.onFinish = { [weak self] item in
            guard let self else { return }
            let query = panel.query // Read before the coordinator hides the panel.
            onFinish?()
            guard let item else { return }
            history.record(query: query, itemID: item.id)
            store.setLauncherHistory(history)
            open(item)
        }
    }

    /// Scans ahead of the first use so the first keystroke already has results.
    func prewarm() { catalog.refresh() }

    func show() {
        history = store.launcherHistory // Restore Defaults may have cleared it meanwhile.
        catalog.refresh()
        panel.show()
    }

    func hide() { panel.hide() }

    private func icon(for item: LauncherItem) -> NSImage {
        if let cached = icons[item.id] { return cached }
        let image = item.kind == .application ? NSWorkspace.shared.icon(forFile: item.id) : settingsIcon
        icons[item.id] = image
        return image
    }

    private func open(_ item: LauncherItem) {
        switch item.kind {
        case .application:
            // The default configuration activates the app, or brings a running one forward.
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.id),
                                               configuration: NSWorkspace.OpenConfiguration()) { [logger] _, error in
                guard let error else { return }
                logger.error("Could not open \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in NSSound.beep() }
            }
        case .settingsPane:
            guard let url = URL(string: "x-apple.systempreferences:\(item.id)") else { return }
            if !NSWorkspace.shared.open(url) {
                logger.error("Could not open settings pane \(item.id, privacy: .public)")
                NSSound.beep()
            }
        }
    }
}
