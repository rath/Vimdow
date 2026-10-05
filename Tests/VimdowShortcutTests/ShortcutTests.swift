import AppKit
import KeyboardShortcuts
import Testing
import VimdowCore

/// Run explicitly on an interactive Mac; this briefly registers the real global shortcuts.
@Suite(.serialized)
@MainActor
struct ShortcutTests {
    @Test func unboundKeysReportActivityOnlyDuringNumberSelection() throws {
        _ = NSApplication.shared
        let controller = ShortcutController(namespace: "test_\(UUID().uuidString)") { _ in }
        defer { cleanUp(controller) }
        var activity = 0
        controller.onInput = { activity += 1 }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
        controller.setMode(.command)
        NSApp.sendEvent(event)
        #expect(activity == 0)
        controller.setMode(.quickSwitch)
        controller.setMode(.quickSwitch) // Paging must not duplicate observers.
        NSApp.sendEvent(event)
        #expect(activity == 1)
        for mode in [Mode.normal, .search, .settings] {
            controller.setMode(mode)
            NSApp.sendEvent(event)
        }
        #expect(activity == 1)
        controller.setMode(.quickSwitch)
        controller.stop()
        NSApp.sendEvent(event)
        #expect(activity == 1)
    }

    @Test(arguments: [-1, 1])
    func markedWindowShortcutsAreSinglePressAndTheGlobalBindingPersists(_ step: Int) throws {
        let namespace = "test_\(UUID().uuidString)"
        let controller = ShortcutController(namespace: namespace) { _ in }
        defer { cleanUp(controller) }
        let cycle = try #require(controller.bindings.first {
            if case .cycleMarked(let direction) = $0.command { direction == step } else { false }
        })
        let initial = KeyboardShortcuts.Shortcut(step < 0 ? .leftBracket : .rightBracket, modifiers: [.control, .option])
        let other = try #require(controller.bindings.first {
            if case .cycleMarked(let direction) = $0.command { direction == -step } else { false }
        })
        let otherShortcut = try #require(other.name.shortcut)
        if case .disallow = controller.validate(otherShortcut, for: cycle.name) {} else {
            Issue.record("Duplicate marked-window shortcut accepted")
        }
        let toggle = try #require(controller.bindings.first { if case .toggleMark = $0.command { true } else { false } })
        #expect(cycle.isGlobal && !cycle.repeats)
        #expect(!toggle.isGlobal && !toggle.repeats)
        #expect(controller.editableBindings.count == 7)
        #expect(controller.editableBindings.contains { $0.name == cycle.name })
        #expect(cycle.name.shortcut == initial)
        #expect(toggle.name.shortcut == KeyboardShortcuts.Shortcut(.m))
        let replacement = KeyboardShortcuts.Shortcut(.tab, modifiers: [.control, .shift])
        cycle.name.shortcut = replacement
        controller.stop()
        let recreated = ShortcutController(namespace: namespace) { _ in }
        defer { recreated.stop() }
        #expect(recreated.bindings.first { $0.name == cycle.name }?.name.shortcut == replacement)
        cycle.name.shortcut = nil
        recreated.stop()
        let cleared = ShortcutController(namespace: namespace) { _ in }
        defer { cleared.stop() }
        #expect(cycle.name.shortcut == nil)
        #expect(other.name.shortcut == otherShortcut)
        #expect(cleared.setMode(.normal).isEmpty)
        #expect(!KeyboardShortcuts.isEnabled(for: cycle.name))
        cleared.restoreDefaults()
        #expect(cycle.name.shortcut == initial)
    }

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

    @Test(arguments: [false, true])
    func formerMarkedDefaultMigratesOnceIncludingLegacyNames(_ legacy: Bool) throws {
        let namespace = "test_\(UUID().uuidString)"
        let old = KeyboardShortcuts.Shortcut(.tab, modifiers: [.control, .option])
        let oldKey = "KeyboardShortcuts_\(namespace)\(legacy ? ".marks.next" : "_marks_next")"
        UserDefaults.standard.set(String(decoding: try JSONEncoder().encode(old), as: UTF8.self), forKey: oldKey)
        defer { UserDefaults.standard.removeObject(forKey: oldKey) }
        let controller = ShortcutController(namespace: namespace) { _ in }
        defer { cleanUp(controller) }
        let next = try #require(controller.bindings.first { $0.name.rawValue == "\(namespace)_marks_next" })
        #expect(next.name.shortcut == KeyboardShortcuts.Shortcut(.rightBracket, modifiers: [.control, .option]))
        if legacy { #expect(UserDefaults.standard.object(forKey: oldKey) == nil) }
        next.name.shortcut = old
        controller.stop()
        let recreated = ShortcutController(namespace: namespace) { _ in }
        defer { recreated.stop() }
        #expect(next.name.shortcut == old)
    }

    @Test(arguments: [false, true], [false, true])
    func markedMigrationPreservesCustomAndClearedBindings(_ legacy: Bool, _ cleared: Bool) throws {
        let namespace = "test_\(UUID().uuidString)"
        let replacement = KeyboardShortcuts.Shortcut(.tab, modifiers: [.control, .shift])
        let oldKey = "KeyboardShortcuts_\(namespace)\(legacy ? ".marks.next" : "_marks_next")"
        if cleared {
            UserDefaults.standard.set(false, forKey: oldKey)
        } else {
            UserDefaults.standard.set(String(decoding: try JSONEncoder().encode(replacement), as: UTF8.self), forKey: oldKey)
        }
        defer { UserDefaults.standard.removeObject(forKey: oldKey) }
        let controller = ShortcutController(namespace: namespace) { _ in }
        defer { cleanUp(controller) }
        let next = try #require(controller.bindings.first { $0.name.rawValue == "\(namespace)_marks_next" })
        #expect(next.name.shortcut == (cleared ? nil : replacement))
        let previous = try #require(controller.bindings.first { $0.name.rawValue == "\(namespace)_marks_previous" })
        #expect(previous.name.shortcut == KeyboardShortcuts.Shortcut(.leftBracket, modifiers: [.control, .option]))
    }

    private func cleanUp(_ controller: ShortcutController) {
        controller.stop()
        for binding in controller.bindings {
            KeyboardShortcuts.setShortcut(nil, for: binding.name)
            UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(binding.name.rawValue)")
            UserDefaults.standard.removeObject(forKey: "\(binding.name.rawValue)_bracketDefaultMigrated")
        }
    }
}
