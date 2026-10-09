import AppKit
import KeyboardShortcuts
import Testing
import VimdowCore

// Share the serialized suite with search tests: both exercise real key windows.
extension SearchPanelTests {
    @Test func settingsPersistValidateAndResetIndependentlyOfShortcuts() throws {
        let suite = "settings_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.preferences == WindowPreferences())
        #expect(!store.showsTmuxPaneNumbers)
        var tmuxChanges: [Bool] = []
        store.onTmuxPaneNumbersChange = { tmuxChanges.append($0) }
        store.setShowsTmuxPaneNumbers(true)
        store.setShowsTmuxPaneNumbers(true)
        #expect(tmuxChanges == [true])
        #expect(!store.dimsOtherWindows)
        #expect(store.dimIntensity == 50)
        var dimChanges: [Bool] = []
        var intensityChanges: [Int] = []
        store.onDimmingChange = { dimChanges.append($0) }
        store.onDimIntensityChange = { intensityChanges.append($0) }
        store.setDimsOtherWindows(true)
        store.setDimsOtherWindows(true)
        #expect(dimChanges == [true])
        for percent in [95, 3, 70, 70] { store.setDimIntensity(percent) }
        #expect(intensityChanges == [90, 10, 70])
        #expect(store.setStep("7", resizing: false))
        #expect(store.setStep("31", resizing: true))
        for invalid in ["", "0", "201", "2.5", "한", "999999999999999999999999"] {
            #expect(!store.setStep(invalid, resizing: false))
        }
        var resets = 0
        store.onDisplayBehaviorChange = { resets += 1 }
        store.setDisplayBehavior(.keepSize)
        store.setDisplayBehavior(.keepSize)
        #expect(resets == 1)
        store.setResizeStopsAtDisplayEdges(false)
        store.setAnimatesSteps(false)
        #expect(store.launcherHistory == LauncherHistory())
        var history = LauncherHistory()
        history.record(query: "s", itemID: "/Applications/Slack.app")
        store.setLauncherHistory(history)
        let recreated = SettingsStore(defaults: defaults)
        #expect(recreated.launcherHistory == history)
        defaults.set(Data([1, 2, 3]), forKey: "launcherHistory")
        #expect(recreated.launcherHistory == LauncherHistory())
        store.setLauncherHistory(history)
        #expect(recreated.showsTmuxPaneNumbers)
        #expect(recreated.dimsOtherWindows)
        #expect(recreated.dimIntensity == 70)
        defaults.set("x", forKey: "dimIntensity")
        #expect(recreated.dimIntensity == 50)
        defaults.set(400, forKey: "dimIntensity")
        #expect(recreated.dimIntensity == 90)
        store.setDimIntensity(70)
        #expect(intensityChanges == [90, 10, 70, 70])
        #expect(recreated.preferences == WindowPreferences(moveStep: 7, resizeStep: 31, displayBehavior: .keepSize,
                                                           resizeStopsAtDisplayEdges: false, animatesSteps: false))
        defaults.set("unrelated", forKey: "anotherPreference")
        store.restoreDefaults()
        #expect(resets == 2)
        #expect(recreated.preferences == WindowPreferences())
        #expect(!recreated.showsTmuxPaneNumbers)
        #expect(recreated.launcherHistory == LauncherHistory())
        #expect(tmuxChanges == [true, false])
        #expect(dimChanges == [true, false])
        #expect(intensityChanges == [90, 10, 70, 70, 50])
        #expect(!recreated.dimsOtherWindows)
        #expect(recreated.dimIntensity == 50)
        #expect(defaults.string(forKey: "anotherPreference") == "unrelated")
    }

    @Test func settingsReuseWindowValidateInputAndResumeShortcuts() async throws {
        try await withSettings { store, shortcuts, controller in
            var active = false
            controller.onActivationChange = {
                active = $0
                shortcuts.setMode($0 ? .settings : .normal)
            }
            controller.show()
            let window = try #require(controller.window)
            controller.show()
            #expect(controller.window === window)
            #expect(window.isVisible)
            // Unhosted xctest cannot reliably activate a regular app window.
            // Native key-window activation is checked in the standalone app.
            #expect(active)
            #expect(shortcuts.bindings.allSatisfy { !KeyboardShortcuts.isEnabled(for: $0.name) })
            window.makeFirstResponder(controller.moveField)
            let editor = try #require(controller.moveField.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("43", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(store.preferences.moveStep == 43)
            editor.selectAll(nil)
            editor.insertText("201", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(store.preferences.moveStep == 43)
            window.makeFirstResponder(controller.resizeField)
            #expect(controller.moveField.integerValue == 43)
            window.close()
            await Task.yield()
            #expect(!active)
            #expect(shortcuts.editableBindings.filter { $0.name.shortcut != nil }.allSatisfy { KeyboardShortcuts.isEnabled(for: $0.name) })
        }
    }

    @Test func checkboxesShowAndSaveWindowPreferences() async throws {
        try await withSettings { store, _, controller in
            controller.show()
            let checkboxes: [(NSButton, KeyPath<WindowPreferences, Bool>)] = [
                (controller.stopAtEdges, \.resizeStopsAtDisplayEdges), (controller.animateSteps, \.animatesSteps),
            ]
            for (checkbox, preference) in checkboxes {
                #expect(checkbox.state == .on)
                checkbox.performClick(nil)
                #expect(checkbox.state == .off)
                #expect(!store.preferences[keyPath: preference])
                checkbox.performClick(nil)
                #expect(store.preferences[keyPath: preference])
            }
            #expect(controller.tmuxPaneNumbers.state == .off)
            controller.tmuxPaneNumbers.performClick(nil)
            #expect(store.showsTmuxPaneNumbers)
            controller.tmuxPaneNumbers.performClick(nil)
            #expect(!store.showsTmuxPaneNumbers)
            store.setShowsTmuxPaneNumbers(true)
            controller.close()
            controller.show()
            #expect(controller.tmuxPaneNumbers.state == .on)
        }
    }

    @Test func dimmingControlsShowAndSaveTheirValues() async throws {
        try await withSettings { store, _, controller in
            controller.show()
            #expect(controller.dimOtherWindows.state == .off)
            controller.dimOtherWindows.performClick(nil)
            #expect(store.dimsOtherWindows)
            controller.dimOtherWindows.performClick(nil)
            #expect(!store.dimsOtherWindows)
            #expect(controller.dimIntensity.integerValue == 50)
            #expect(controller.dimIntensityLabel.stringValue == "50 %")
            controller.dimIntensity.integerValue = 80
            #expect(controller.dimIntensity.sendAction(controller.dimIntensity.action, to: controller.dimIntensity.target))
            #expect(store.dimIntensity == 80)
            #expect(controller.dimIntensityLabel.stringValue == "80 %")
            store.setDimIntensity(30)
            store.setDimsOtherWindows(true)
            controller.close()
            controller.show()
            #expect(controller.dimOtherWindows.state == .on)
            #expect(controller.dimIntensity.integerValue == 30)
            #expect(controller.dimIntensityLabel.stringValue == "30 %")
            store.restoreDefaults()
            controller.close()
            controller.show()
            #expect(controller.dimOtherWindows.state == .off)
            #expect(controller.dimIntensity.integerValue == 50)
            #expect(controller.dimIntensityLabel.stringValue == "50 %")
        }
    }

    private func withSettings(_ body: (SettingsStore, ShortcutController, SettingsWindowController) async throws -> Void) async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "settings_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = SettingsStore(defaults: defaults)
        let shortcuts = ShortcutController(namespace: suite) { _ in }
        let controller = SettingsWindowController(store: store, shortcuts: shortcuts, permissionGranted: { false })
        defer {
            controller.close()
            shortcuts.stop()
            for binding in shortcuts.bindings {
                KeyboardShortcuts.setShortcut(nil, for: binding.name)
                UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(binding.name.rawValue)")
                UserDefaults.standard.removeObject(forKey: "\(binding.name.rawValue)_bracketDefaultMigrated")
            }
            defaults.removePersistentDomain(forName: suite)
        }
        try await body(store, shortcuts, controller)
    }
}
