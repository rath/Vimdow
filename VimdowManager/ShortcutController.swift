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
    var onInput: (() -> Void)?
    private var inputMonitors: [Any] = []
    private var tasks: [Task<Void, Never>] = []
    private let onCommand: (Command) -> Void
    private let namespace: String

    init(namespace: String = "vimdow", onCommand: @escaping (Command) -> Void) {
        self.onCommand = onCommand
        self.namespace = namespace
        Self.migrateMarkedShortcut(namespace: namespace)
        add("enter", .a, [.control, .option], .enter, global: true, title: "Enter command mode")
        add("marks.previous", .leftBracket, [.control, .option], .cycleMarked(-1), global: true, title: "Previous marked window")
        add("marks.next", .rightBracket, [.control, .option], .cycleMarked(1), global: true, title: "Next marked window")
        add("marks.toggle", .m, [], .toggleMark)
        for (key, direction) in [(KeyboardShortcuts.Key.h, Direction.left), (.j, .down), (.k, .up), (.l, .right)] {
            let step = direction == .left || direction == .down ? -1 : 1
            add("cycle.\(key.rawValue)", key, [.control, .shift], .cycle(step), global: true, repeats: true,
                title: "\(step < 0 ? "Previous" : "Next") window (\(direction == .left ? "H" : direction == .down ? "J" : direction == .up ? "K" : "L"))")
            add("move.\(key.rawValue)", key, [], .move(direction), repeats: true)
            add("resize.topLeft.\(key.rawValue)", key, [.option], .resize(direction, .topLeft), repeats: true)
            add("resize.bottomRight.\(key.rawValue)", key, [.shift], .resize(direction, .bottomRight), repeats: true)
        }
        add("undo", .u, [], .undo)
        add("redo", .r, [.control], .redo)
        add("place.right", .four, [.shift], .place(.edge(.right))) // $
        add("place.bottom", .g, [.shift], .place(.edge(.down))) // G
        add("sequence.g", .g, [], .sequence(.g))
        add("sequence.z", .z, [], .sequence(.z))
        add("sequence.window", .w, [.control], .sequence(.window))
        add("sequence.o", .o, [], .sequence(.only))
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
        monitorInput(mode == .quickSwitch)
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

    /// Run before Name initialization, which persists initial shortcuts.
    static func migrateMarkedShortcut(namespace: String, defaults: UserDefaults = .standard) {
        let name = "\(namespace)_marks_next"
        migrateShortcut(from: "\(namespace).marks.next", to: name, defaults: defaults)
        let migratedKey = "\(name)_bracketDefaultMigrated"
        guard !defaults.bool(forKey: migratedKey) else { return }
        let shortcutKey = "KeyboardShortcuts_\(name)"
        if let saved = defaults.string(forKey: shortcutKey),
           let data = saved.data(using: .utf8),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data),
           shortcut == KeyboardShortcuts.Shortcut(.tab, modifiers: [.control, .option]) {
            // Let the new initial shortcut replace only the former default.
            defaults.removeObject(forKey: shortcutKey)
        }
        // A later explicit reassignment to Tab must survive subsequent launches.
        defaults.set(true, forKey: migratedKey)
    }

    func stop() {
        monitorInput(false)
        KeyboardShortcuts.disable(bindings.map(\.name))
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        bindings.forEach { KeyboardShortcuts.removeHandler(for: $0.name) }
    }

    private func monitorInput(_ enabled: Bool) {
        if !enabled {
            inputMonitors.forEach { NSEvent.removeMonitor($0) }
            inputMonitors.removeAll()
            return
        }
        guard inputMonitors.isEmpty else { return }
        // Event monitors run on the main thread. They observe unbound keys;
        // registered Carbon shortcuts refresh the timer through handle(_:).
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onInput?() }
        }) {
            inputMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.onInput?() }
            return event
        }) {
            inputMonitors.append(monitor)
        }
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
