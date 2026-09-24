import AppKit
import KeyboardShortcuts
import VimdowCore

@MainActor
final class ShortcutController {
    struct Binding {
        let name: KeyboardShortcuts.Name
        let title: String
        let command: Command
        let isGlobal: Bool
        let repeats: Bool
    }

    private(set) var bindings: [Binding] = []
    private var tasks: [Task<Void, Never>] = []
    private let onCommand: (Command) -> Void
    private let namespace: String

    init(namespace: String = "vimdow", onCommand: @escaping (Command) -> Void) {
        self.onCommand = onCommand
        self.namespace = namespace
        add("enter", .a, [.control, .option], .enter, global: true, title: "Enter command mode")
        for (key, direction) in [(KeyboardShortcuts.Key.h, Direction.left), (.j, .down), (.k, .up), (.l, .right)] {
            let step = direction == .left || direction == .down ? -1 : 1
            add("cycle.\(key.rawValue)", key, [.control, .shift], .cycle(step), global: true, repeats: true,
                title: "\(step < 0 ? "Previous" : "Next") window (\(direction == .left ? "H" : direction == .down ? "J" : direction == .up ? "K" : "L"))")
            add("move.\(key.rawValue)", key, [], .move(direction), repeats: true)
            add("resize.topLeft.\(key.rawValue)", key, [.option], .resize(direction, .topLeft), repeats: true)
            add("resize.bottomRight.\(key.rawValue)", key, [.shift], .resize(direction, .bottomRight), repeats: true)
        }
        add("escape", .escape, [], .escape)
        add("period", .period, [], .escape)
        add("quickSwitch", .q, [], .quickSwitch)
        add("search", .slash, [], .search)
        add("settings", .comma, [], .settings)
        add("search.next", .n, [], .repeatSearch(1))
        add("search.previous", .n, [.shift], .repeatSearch(-1))
        add("screen.k", .k, [.control, .option], .nextScreen)
        add("screen.l", .l, [.control, .option], .nextScreen)
        add("quit", .x, [], .quit)
        let digits: [KeyboardShortcuts.Key] = [.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        for (digit, key) in digits.enumerated() { add("digit.\(digit)", key, [], .digit(digit)) }
        installHandlers()
    }

    /// Returns conflicts instead of silently pretending a shortcut was registered.
    @discardableResult
    func setMode(_ mode: Mode) -> [String] {
        let enabled = bindings.filter { binding in
            switch mode {
            case .normal: binding.isGlobal
            case .command, .quickSwitch: true
            case .search, .settings: false // Native controls own text input and shortcut recording.
            }
        }
        let names = Set(enabled.map(\.name))
        KeyboardShortcuts.disable(bindings.filter { !names.contains($0.name) }.map(\.name))
        let assigned = enabled.filter { $0.name.shortcut != nil }
        KeyboardShortcuts.enable(assigned.map(\.name))
        return assigned.filter { !KeyboardShortcuts.isEnabled(for: $0.name) }.compactMap { $0.name.shortcut?.description }
    }

    var editableBindings: [Binding] { bindings.filter(\.isGlobal) }

    func validate(_ shortcut: KeyboardShortcuts.Shortcut, for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.ValidationResult {
        if bindings.contains(where: { $0.name != name && $0.name.shortcut == shortcut }) {
            return .disallow(reason: "This shortcut is already assigned to another Vimdow command.")
        }
        return .allow
    }

    func restoreDefaults() {
        KeyboardShortcuts.reset(editableBindings.map(\.name))
    }

    static func migrateShortcut(from old: String, to new: String, defaults: UserDefaults = .standard) {
        let oldKey = "KeyboardShortcuts_\(old)", newKey = "KeyboardShortcuts_\(new)"
        if defaults.object(forKey: newKey) == nil, let saved = defaults.object(forKey: oldKey) {
            defaults.set(saved, forKey: newKey)
        }
        defaults.removeObject(forKey: oldKey)
    }

    func stop() {
        KeyboardShortcuts.disable(bindings.map(\.name))
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        bindings.forEach { KeyboardShortcuts.removeHandler(for: $0.name) }
    }

    private func add(
        _ identifier: String, _ key: KeyboardShortcuts.Key, _ modifiers: NSEvent.ModifierFlags,
        _ command: Command, global: Bool = false, repeats: Bool = false, title: String = ""
    ) {
        let rawName = "\(namespace)_\(identifier.replacingOccurrences(of: ".", with: "_"))"
        Self.migrateShortcut(from: "\(namespace).\(identifier)", to: rawName)
        bindings.append(Binding(name: .init(rawName, initial: .init(key, modifiers: modifiers)), title: title,
                                command: command, isGlobal: global, repeats: repeats))
    }

    private func installHandlers() {
        for binding in bindings {
            KeyboardShortcuts.disable(binding.name)
            if binding.repeats {
                let events = KeyboardShortcuts.repeatingKeyDownEvents(for: binding.name)
                tasks.append(Task { [weak self] in
                    for await _ in events {
                        guard !Task.isCancelled else { break }
                        if KeyboardShortcuts.isEnabled(for: binding.name) { self?.onCommand(binding.command) }
                    }
                })
            } else {
                KeyboardShortcuts.onKeyDown(for: binding.name) { [weak self] in
                    // Leave the Carbon callback before unregistering any active hotkey.
                    Task { @MainActor [weak self] in
                        if KeyboardShortcuts.isEnabled(for: binding.name) { self?.onCommand(binding.command) }
                    }
                }
            }
        }
    }
}
