import Foundation
import VimdowCore

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    var onDisplayBehaviorChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

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
        for key in ["windowMoveStep", "windowResizeStep", "displayMoveBehavior", "resizeStopsAtDisplayEdges",
                    "animatesSteps"] {
            defaults.removeObject(forKey: key)
        }
        if previous != preferences.displayBehavior { onDisplayBehaviorChange?() }
    }
}
