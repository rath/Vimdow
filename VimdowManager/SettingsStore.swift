import Foundation
import VimdowCore

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    var onDisplayBehaviorChange: (() -> Void)?
    var onTmuxPaneNumbersChange: ((Bool) -> Void)?
    var onDimmingChange: ((Bool) -> Void)?
    var onDimIntensityChange: ((Int) -> Void)?
    static let dimIntensityRange = 10...90
    static let defaultDimIntensity = 50

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var showsTmuxPaneNumbers: Bool { defaults.bool(forKey: "showsTmuxPaneNumbers") }

    var dimsOtherWindows: Bool { defaults.bool(forKey: "dimsOtherWindows") }

    /// Black alpha of the dimming sheets in percent. Unreadable values use the default;
    /// values outside the range are read as its nearest bound.
    var dimIntensity: Int {
        guard let value = defaults.object(forKey: "dimIntensity") as? Int else { return Self.defaultDimIntensity }
        return Self.clampDimIntensity(value)
    }

    func setDimsOtherWindows(_ enabled: Bool) {
        let previous = dimsOtherWindows
        defaults.set(enabled, forKey: "dimsOtherWindows")
        if previous != enabled { onDimmingChange?(enabled) }
    }

    func setDimIntensity(_ percent: Int) {
        let previous = dimIntensity
        let value = Self.clampDimIntensity(percent)
        defaults.set(value, forKey: "dimIntensity")
        if previous != value { onDimIntensityChange?(value) }
    }

    private static func clampDimIntensity(_ value: Int) -> Int {
        min(max(value, dimIntensityRange.lowerBound), dimIntensityRange.upperBound)
    }

    /// Queries and the launcher items chosen for them. Unreadable data counts as empty.
    var launcherHistory: LauncherHistory {
        guard let data = defaults.data(forKey: "launcherHistory"),
              let history = try? JSONDecoder().decode(LauncherHistory.self, from: data) else { return LauncherHistory() }
        return history
    }

    func setLauncherHistory(_ history: LauncherHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: "launcherHistory")
    }

    func setShowsTmuxPaneNumbers(_ enabled: Bool) {
        let previous = showsTmuxPaneNumbers
        defaults.set(enabled, forKey: "showsTmuxPaneNumbers")
        if previous != enabled { onTmuxPaneNumbersChange?(enabled) }
    }

    var preferences: WindowPreferences {
        WindowPreferences(moveStep: defaults.object(forKey: "windowMoveStep") as? Int ?? 20,
                          resizeStep: defaults.object(forKey: "windowResizeStep") as? Int ?? 20,
                          displayBehavior: DisplayMoveBehavior(rawValue:
                            defaults.string(forKey: "displayMoveBehavior") ?? "") ?? .fillDisplay,
                          resizeStopsAtDisplayEdges: defaults.object(forKey: "resizeStopsAtDisplayEdges") as? Bool ?? true,
                          animatesSteps: defaults.object(forKey: "animatesSteps") as? Bool ?? true)
    }

    @discardableResult
    func setStep(_ text: String, resizing: Bool) -> Bool {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...200).contains(value) else { return false }
        defaults.set(value, forKey: resizing ? "windowResizeStep" : "windowMoveStep")
        return true
    }

    func setDisplayBehavior(_ behavior: DisplayMoveBehavior) {
        let previous = preferences.displayBehavior
        defaults.set(behavior.rawValue, forKey: "displayMoveBehavior")
        if previous != behavior { onDisplayBehaviorChange?() }
    }

    func setResizeStopsAtDisplayEdges(_ enabled: Bool) {
        defaults.set(enabled, forKey: "resizeStopsAtDisplayEdges")
    }

    func setAnimatesSteps(_ enabled: Bool) {
        defaults.set(enabled, forKey: "animatesSteps")
    }

    func restoreDefaults() {
        let previous = preferences.displayBehavior
        let tmuxWasEnabled = showsTmuxPaneNumbers
        let dimWasEnabled = dimsOtherWindows
        let previousIntensity = dimIntensity
        for key in ["windowMoveStep", "windowResizeStep", "displayMoveBehavior", "resizeStopsAtDisplayEdges",
                    "animatesSteps", "showsTmuxPaneNumbers", "launcherHistory", "dimsOtherWindows", "dimIntensity"] {
            defaults.removeObject(forKey: key)
        }
        if previous != preferences.displayBehavior { onDisplayBehaviorChange?() }
        if tmuxWasEnabled { onTmuxPaneNumbersChange?(false) }
        if dimWasEnabled { onDimmingChange?(false) }
        if previousIntensity != dimIntensity { onDimIntensityChange?(dimIntensity) }
    }
}
