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
        let controller = ShortcutController { _ in }
        defer { controller.stop() }
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
        #expect(controller.setMode(.normal).isEmpty)
        for binding in controller.bindings {
            #expect(KeyboardShortcuts.isEnabled(for: binding.name) == binding.isGlobal)
        }
        controller.stop()
        await Task.yield()
        for binding in controller.bindings { #expect(!KeyboardShortcuts.isEnabled(for: binding.name)) }
    }
}
