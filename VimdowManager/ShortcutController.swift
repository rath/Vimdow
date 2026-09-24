import AppKit
import KeyboardShortcuts
import VimdowCore

@MainActor
final class ShortcutController {
    struct Binding {
        let name: KeyboardShortcuts.Name
        let shortcut: KeyboardShortcuts.Shortcut
        let command: Command
        let isGlobal: Bool
        let repeats: Bool
    }

    private(set) var bindings: [Binding] = []
    private var tasks: [Task<Void, Never>] = []
    private let onCommand: (Command) -> Void

    init(onCommand: @escaping (Command) -> Void) {
        self.onCommand = onCommand
        add("enter", .a, [.control, .option], .enter, global: true)
        for (key, direction) in [(KeyboardShortcuts.Key.h, Direction.left), (.j, .down), (.k, .up), (.l, .right)] {
            let step = direction == .left || direction == .down ? -1 : 1
            add("cycle.\(key.rawValue)", key, [.control, .shift], .cycle(step), global: true, repeats: true)
            add("move.\(key.rawValue)", key, [], .move(direction), repeats: true)
            add("resize.topLeft.\(key.rawValue)", key, [.option], .resize(direction, .topLeft), repeats: true)
            add("resize.bottomRight.\(key.rawValue)", key, [.shift], .resize(direction, .bottomRight), repeats: true)
        }
        add("escape", .escape, [], .escape)
        add("period", .period, [], .escape)
        add("quickSwitch", .q, [], .quickSwitch)
        add("search", .slash, [], .search)
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
            case .search: false // NSTextField owns Escape and text input, including IME composition.
            }
        }
        let names = Set(enabled.map(\.name))
        KeyboardShortcuts.disable(bindings.filter { !names.contains($0.name) }.map(\.name))
        KeyboardShortcuts.enable(enabled.map(\.name))
        return enabled.filter { !KeyboardShortcuts.isEnabled(for: $0.name) }.map { $0.shortcut.description }
    }

    func stop() {
        KeyboardShortcuts.disable(bindings.map(\.name))
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        bindings.forEach { KeyboardShortcuts.removeHandler(for: $0.name) }
    }

    private func add(
        _ identifier: String, _ key: KeyboardShortcuts.Key, _ modifiers: NSEvent.ModifierFlags,
        _ command: Command, global: Bool = false, repeats: Bool = false
    ) {
        bindings.append(Binding(name: .init("vimdow.\(identifier)"), shortcut: .init(key, modifiers: modifiers),
                                command: command, isGlobal: global, repeats: repeats))
    }

    private func installHandlers() {
        for binding in bindings {
            KeyboardShortcuts.disable(binding.name)
            KeyboardShortcuts.setShortcut(binding.shortcut, for: binding.name)
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
