import AppKit
import ApplicationServices
import KeyboardShortcuts
import VimdowCore

private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let store: SettingsStore
    private let shortcuts: ShortcutController
    private let permissionGranted: () -> Bool
    var onActivationChange: ((Bool) -> Void)?
    private(set) var moveField = NSTextField(string: "20")
    private(set) var resizeField = NSTextField(string: "20")
    private(set) var tabs = NSTabView()
    private(set) var stopAtEdges = NSButton(checkboxWithTitle: "Stop resizing at display edges", target: nil, action: nil)
    private(set) var animateSteps = NSButton(checkboxWithTitle: "Animate moving and resizing", target: nil, action: nil)
    private let moveStepper = NSStepper()
    private let resizeStepper = NSStepper()
    private let behavior = NSPopUpButton()
    private let validation = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(labelWithString: "")

    init(store: SettingsStore, shortcuts: ShortcutController,
         permissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.store = store
        self.shortcuts = shortcuts
        self.permissionGranted = permissionGranted
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Vimdow Settings"
        window.minSize = NSSize(width: 620, height: 580)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("VimdowSettings")
        buildContent()
        refreshGeneral()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationResigned),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:shortcuts:)") }

    func show() {
        refreshPermission()
        onActivationChange?(true)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermission()
        onActivationChange?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Recorder validation can show a sheet; its text input still belongs to Settings.
        Task { @MainActor [weak self] in
            guard let self, let window else { return }
            onActivationChange?(window.isVisible && NSApp.isActive && (window.isKeyWindow || window.attachedSheet != nil))
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onActivationChange?(false)
    }

    @objc private func applicationResigned() { onActivationChange?(false) }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field == moveField || field == resizeField,
              (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        if store.setStep(field.stringValue, resizing: field == resizeField) {
            (field == resizeField ? resizeStepper : moveStepper).integerValue = field.integerValue
        }
        updateValidation()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field == moveField || field == resizeField else { return }
        _ = store.setStep(field.stringValue, resizing: field == resizeField)
        let value = field == resizeField ? store.preferences.resizeStep : store.preferences.moveStep
        field.integerValue = value
        (field == resizeField ? resizeStepper : moveStepper).integerValue = value
        updateValidation()
    }

    private func updateValidation() {
        let valid = [moveField, resizeField].allSatisfy {
            guard let value = Int($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return (1...200).contains(value)
        }
        validation.stringValue = valid ? "" : "Enter a whole number from 1 to 200. Invalid input is discarded when you leave the field."
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        addTab("General", content: generalContent())
        addTab("Shortcuts", content: shortcutsContent())
    }

    private func addTab(_ title: String, content: NSStackView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = scroll
        tabs.addTabViewItem(item)
    }

    private func generalContent() -> NSStackView {
        let stack = column()
        stack.addArrangedSubview(heading("Window behavior"))
        stack.addArrangedSubview(note("Changes apply immediately and are saved automatically."))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Move by"), stepControl(moveField, stepper: moveStepper, identifier: "moveStep")],
            [NSTextField(labelWithString: "Resize by"), stepControl(resizeField, stepper: resizeStepper, identifier: "resizeStep")],
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 20
        grid.yPlacement = .center
        stack.addArrangedSubview(grid)
        stack.setCustomSpacing(4, after: grid)
        validation.textColor = .systemRed
        validation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        stack.addArrangedSubview(validation)
        stopAtEdges.target = self
        stopAtEdges.action = #selector(stopAtEdgesChanged)
        stack.addArrangedSubview(stopAtEdges)
        stack.setCustomSpacing(4, after: stopAtEdges)
        stack.addArrangedSubview(note("Enlarging a window stops at the menu bar, the Dock, and the edges of its display."))
        animateSteps.target = self
        animateSteps.action = #selector(animateStepsChanged)
        stack.addArrangedSubview(animateSteps)
        stack.addArrangedSubview(heading("Moving between displays"))
        behavior.addItems(withTitles: ["Fill Display", "Keep Size"])
        behavior.target = self
        behavior.action = #selector(behaviorChanged)
        behavior.setAccessibilityLabel("First move to a display")
        stack.addArrangedSubview(behavior)
        stack.addArrangedSubview(note("Used on the first visit to a display. Return visits restore the window’s last position and size. Changing this setting clears remembered positions."))
        stack.addArrangedSubview(heading("Accessibility"))
        stack.addArrangedSubview(permission)
        stack.addArrangedSubview(button("Open System Settings", action: #selector(openAccessibility)))
        stack.addArrangedSubview(note("Vimdow needs Accessibility permission to control other apps. You can edit these settings without granting permission."))
        stack.addArrangedSubview(button("Restore Defaults", action: #selector(resetGeneral)))
        return stack
    }

    private func shortcutsContent() -> NSStackView {
        let stack = column()
        stack.addArrangedSubview(heading("Global shortcuts"))
        stack.addArrangedSubview(note("Click a shortcut to record a new combination. Delete clears it. Reopen Vimdow from Applications if you clear the command-mode shortcut."))
        let rows: [[NSView]] = shortcuts.editableBindings.map { binding in
            let recorder = KeyboardShortcuts.RecorderCocoa(for: binding.name)
            recorder.conflictPolicy = .init(menuItem: .block, systemShortcut: .block, disallowed: .block)
            recorder.validateShortcut = { [weak shortcuts] shortcut in
                shortcuts?.validate(shortcut, for: binding.name) ?? .allow
            }
            recorder.setAccessibilityLabel(binding.title)
            return [NSTextField(labelWithString: binding.title), recorder]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 20
        grid.yPlacement = .center
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(button("Restore Defaults", action: #selector(resetShortcuts)))
        stack.addArrangedSubview(heading("Command mode reference"))
        stack.addArrangedSubview(note("These keys are fixed. Release the entry shortcut before using them."))
        let reference = [
            ("H / J / K / L", "Move left / down / up / right"),
            ("Option–H / J / K / L", "Resize; keep top-left fixed"),
            ("Shift–H / J / K / L", "Resize; keep bottom-right fixed"),
            ("Digits, then move / resize", "Repeat the action"),
            ("Q, then 1–9", "Select a numbered window; Q pages"),
            ("/", "Search by application name"),
            ("N / Shift–N", "Next / previous search match"),
            ("Control–Option–K / L", "Move to the next display"),
            (",", "Open Settings"),
            ("Escape / .", "Exit command mode"),
            ("X", "Quit Vimdow"),
        ]
        let guide = NSGridView(views: reference.map { key, action in
            [NSTextField(labelWithString: key), NSTextField(labelWithString: action)]
        })
        guide.rowSpacing = 9
        guide.columnSpacing = 20
        for view in guide.subviews.compactMap({ $0 as? NSTextField }) { view.font = .systemFont(ofSize: 12) }
        stack.addArrangedSubview(guide)
        return stack
    }

    private func column() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        return stack
    }

    private func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func stepControl(_ field: NSTextField, stepper: NSStepper, identifier: String) -> NSStackView {
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityLabel(identifier == "moveStep" ? "Movement in points" : "Resize in points")
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        stepper.minValue = 1
        stepper.maxValue = 200
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepChanged(_:))
        stepper.setAccessibilityLabel(identifier == "moveStep" ? "Adjust movement" : "Adjust resize")
        let row = NSStackView(views: [field, stepper, NSTextField(labelWithString: "pt")])
        row.spacing = 8
        return row
    }

    private func refreshGeneral() {
        let settings = store.preferences
        moveField.integerValue = settings.moveStep
        resizeField.integerValue = settings.resizeStep
        moveStepper.integerValue = settings.moveStep
        resizeStepper.integerValue = settings.resizeStep
        behavior.selectItem(at: settings.displayBehavior == .fillDisplay ? 0 : 1)
        stopAtEdges.state = settings.resizeStopsAtDisplayEdges ? .on : .off
        animateSteps.state = settings.animatesSteps ? .on : .off
        updateValidation()
        refreshPermission()
    }

    private func refreshPermission() {
        permission.stringValue = permissionGranted() ? "Permission granted" : "Permission required"
    }

    @objc private func stepChanged(_ sender: NSStepper) {
        _ = store.setStep(String(sender.integerValue), resizing: sender == resizeStepper)
        refreshGeneral()
    }

    @objc private func behaviorChanged() {
        store.setDisplayBehavior(behavior.indexOfSelectedItem == 0 ? .fillDisplay : .keepSize)
    }

    @objc private func stopAtEdgesChanged() {
        store.setResizeStopsAtDisplayEdges(stopAtEdges.state == .on)
    }

    @objc private func animateStepsChanged() {
        store.setAnimatesSteps(animateSteps.state == .on)
    }

    @objc private func resetGeneral() {
        window?.makeFirstResponder(nil)
        store.restoreDefaults()
        refreshGeneral()
    }

    @objc private func resetShortcuts() { shortcuts.restoreDefaults() }

    @objc private func openAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
