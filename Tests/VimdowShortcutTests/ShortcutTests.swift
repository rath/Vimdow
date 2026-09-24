import AppKit
import KeyboardShortcuts
import Testing
import VimdowCore

/// Run explicitly on an interactive Mac; this briefly registers the real global shortcuts.
@Suite(.serialized)
@MainActor
struct ShortcutTests {
    @Test func modalKeysRegisterAndAreReleasedOnExitAndSearch() async {
        _ = NSApplication.shared
        let controller = ShortcutController(namespace: "test_\(UUID().uuidString)") { _ in }
        defer { cleanUp(controller) }
        #expect(controller.setMode(.normal).isEmpty)
        for binding in controller.bindings {
            #expect(KeyboardShortcuts.isEnabled(for: binding.name) == binding.isGlobal)
        }
        #expect(controller.setMode(.command).isEmpty)
        #expect(controller.setMode(.command).isEmpty)
        for binding in controller.bindings { #expect(KeyboardShortcuts.isEnabled(for: binding.name)) }
        #expect(controller.setMode(.quickSwitch).isEmpty)
        #expect(controller.setMode(.search).isEmpty)
        for binding in controller.bindings { #expect(!KeyboardShortcuts.isEnabled(for: binding.name)) }
        #expect(controller.setMode(.settings).isEmpty)
        for binding in controller.bindings { #expect(!KeyboardShortcuts.isEnabled(for: binding.name)) }
        #expect(controller.setMode(.normal).isEmpty)
        for binding in controller.bindings {
            #expect(KeyboardShortcuts.isEnabled(for: binding.name) == binding.isGlobal)
        }
        controller.stop()
        await Task.yield()
        for binding in controller.bindings { #expect(!KeyboardShortcuts.isEnabled(for: binding.name)) }
    }

    @Test func editsAndClearedShortcutsSurviveRecreationAndReset() throws {
        let namespace = "test_\(UUID().uuidString)"
        let first = ShortcutController(namespace: namespace) { _ in }
        defer { cleanUp(first) }
        let name = try #require(first.editableBindings.first?.name)
        let replacement = KeyboardShortcuts.Shortcut(.a, modifiers: [.control, .option, .shift])
        name.shortcut = replacement
        first.stop()
        let second = ShortcutController(namespace: namespace) { _ in }
        defer { second.stop() }
        #expect(second.editableBindings.first?.name.shortcut == replacement)
        name.shortcut = nil
        #expect(second.setMode(.normal).isEmpty)
        #expect(!KeyboardShortcuts.isEnabled(for: name))
        second.stop()
        let third = ShortcutController(namespace: namespace) { _ in }
        defer { third.stop() }
        #expect(third.editableBindings.first?.name.shortcut == nil)
        third.restoreDefaults()
        #expect(name.shortcut == KeyboardShortcuts.Shortcut(.a, modifiers: [.control, .option]))
    }

    @Test func duplicateAssignmentsAreRejectedAndNamesHaveNoDots() throws {
        let controller = ShortcutController(namespace: "test_\(UUID().uuidString)") { _ in }
        defer { cleanUp(controller) }
        #expect(controller.bindings.allSatisfy { !$0.name.rawValue.contains(".") })
        let first = try #require(controller.editableBindings.first)
        let other = try #require(controller.editableBindings.last?.name.shortcut)
        if case .disallow = controller.validate(other, for: first.name) {} else { Issue.record("Duplicate accepted") }
        let fixed = try #require(controller.bindings.first(where: { !$0.isGlobal })?.name.shortcut)
        if case .disallow = controller.validate(fixed, for: first.name) {} else { Issue.record("Modal duplicate accepted") }
    }

    @Test func legacyMigrationPreservesDisabledValuesAndDoesNotOverwriteNewValues() throws {
        let suite = "test_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "KeyboardShortcuts_old.key")
        ShortcutController.migrateShortcut(from: "old.key", to: "new_key", defaults: defaults)
        #expect(defaults.object(forKey: "KeyboardShortcuts_new_key") as? Bool == false)
        #expect(defaults.object(forKey: "KeyboardShortcuts_old.key") == nil)
        defaults.set("old value", forKey: "KeyboardShortcuts_old.key")
        ShortcutController.migrateShortcut(from: "old.key", to: "new_key", defaults: defaults)
        #expect(defaults.object(forKey: "KeyboardShortcuts_new_key") as? Bool == false)
    }

    private func cleanUp(_ controller: ShortcutController) {
        controller.stop()
        for binding in controller.bindings {
            KeyboardShortcuts.setShortcut(nil, for: binding.name)
            UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(binding.name.rawValue)")
        }
    }
}
