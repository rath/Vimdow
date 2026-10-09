import AppKit
import VimdowCore

/// The applications and System Settings panes the launcher can open, scanned off the main thread.
@MainActor
final class LauncherCatalog {
    private(set) var items: [LauncherItem] = []
    var onChange: (() -> Void)?
    /// Settings panes only change with the OS, so one scan per process is enough.
    private var panes: [LauncherItem]?
    private var generation = 0

    /// Rescans application folders; a slower older scan never overwrites a newer one.
    func refresh() {
        generation += 1
        let current = generation
        let needsPanes = panes == nil
        Task { [weak self] in
            let applications = await Task.detached(priority: .utility) { LauncherScan.applications() }.value
            let panes = needsPanes ? await Task.detached(priority: .utility) { LauncherScan.settingsPanes() }.value : nil
            guard let self, current == generation else { return }
            if let panes { self.panes = panes }
            items = applications + (self.panes ?? [])
            onChange?()
        }
    }
}

/// Pure Foundation scanning that returns only Sendable values, so it can run on any thread.
enum LauncherScan {
    static let settingsExtensionPoint = "com.apple.Settings.extension.ui"
    static let applicationRoots: [(path: String, depth: Int)] = [
        ("/Applications", 2),
        ("/System/Applications", 1),
        ("/System/Applications/Utilities", 1),
        ("/System/Library/CoreServices/Applications", 1),
        (NSHomeDirectory() + "/Applications", 1),
    ]
    /// Launchable apps that live among background agents, so their folder is not scanned.
    static let standaloneApplications = ["/System/Library/CoreServices/Finder.app"]
    static let paneRoots = [
        "/System/Library/ExtensionKit/Extensions",
        "/System/Applications/System Settings.app/Contents/PlugIns",
    ]
    /// Panes without a human-readable name or with transient content.
    static let excludedPaneIDs: Set<String> = [
        "com.apple.HeadphoneSettings", "com.apple.FollowUpSettings.FollowUpSettingsExtension",
    ]
    /// Panes whose Info.plist name is an internal identifier; their strings table has the real title.
    static let paneNameOverrides: [String: (nameKey: String, aliasKeys: [String])] = [
        "com.apple.Battery-Settings.extension": ("BATTERY_PREF_TITLE", ["ENERGY_SAVER_PREF_TITLE"]),
    ]

    static func applications(fileManager: FileManager = .default) -> [LauncherItem] {
        var seen: Set<String> = []
        var items: [LauncherItem] = []
        func visit(_ directory: URL, depth: Int) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
            for url in entries {
                if url.pathExtension == "app" {
                    guard let item = application(at: url, fileManager: fileManager), !seen.contains(item.id) else { continue }
                    seen.insert(item.id)
                    items.append(item)
                } else if depth > 1, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(url, depth: depth - 1)
                }
            }
        }
        for root in applicationRoots { visit(URL(fileURLWithPath: root.path), depth: root.depth) }
        for path in standaloneApplications {
            guard fileManager.fileExists(atPath: path),
                  let item = application(at: URL(fileURLWithPath: path), fileManager: fileManager),
                  !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            items.append(item)
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func application(at url: URL, fileManager: FileManager) -> LauncherItem? {
        let path = url.resolvingSymlinksInPath().path
        let name = fileManager.displayName(atPath: path)
        guard !name.isEmpty else { return nil }
        let info = Bundle(url: url)?.infoDictionary
        let aliases = [url.deletingPathExtension().lastPathComponent,
                       info?["CFBundleDisplayName"] as? String, info?["CFBundleName"] as? String]
        return LauncherItem(id: path, name: name, aliases: distinct(aliases, excluding: name), kind: .application)
    }

    static func settingsPanes() -> [LauncherItem] {
        var items: [LauncherItem] = []
        for root in paneRoots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for url in entries where url.pathExtension == "appex" {
                if let item = settingsPane(at: url) { items.append(item) }
            }
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func settingsPane(at url: URL) -> LauncherItem? {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
              !excludedPaneIDs.contains(identifier),
              let attributes = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
              attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
              let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true else { return nil }
        let rawDisplayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String
        let rawName = bundle.infoDictionary?["CFBundleName"] as? String
        let override = paneNameOverrides[identifier]
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? override.flatMap { localizedString($0.nameKey, in: bundle) }
            ?? rawDisplayName ?? rawName
        guard let name, !name.isEmpty else { return nil }
        let aliases = (override?.aliasKeys ?? []).map { localizedString($0, in: bundle) } + [rawDisplayName, rawName]
        return LauncherItem(id: identifier, name: name, aliases: distinct(aliases, excluding: name), kind: .settingsPane)
    }

    /// A string from the bundle's default table, or nil when the table has no such key.
    private static func localizedString(_ key: String, in bundle: Bundle) -> String? {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }

    private static func distinct(_ candidates: [String?], excluding name: String) -> [String] {
        var seen: Set<String> = [name]
        return candidates.compactMap { candidate in
            guard let candidate, !candidate.isEmpty, !seen.contains(candidate) else { return nil }
            seen.insert(candidate)
            return candidate
        }
    }
}
