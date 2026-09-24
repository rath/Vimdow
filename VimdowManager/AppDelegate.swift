import AppKit
import ApplicationServices
import OSLog
import VimdowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CommandPresenting {
    private let service = WindowService()
    private let guides = GuideWindows()
    private let search = SearchPanel()
    private let logger = Logger(subsystem: "rath.toys.VimdowManager", category: "WindowControl")
    private lazy var coordinator = CommandCoordinator(windows: service, presentation: self)
    private var shortcuts: ShortcutController?
    private var permissionAlert: NSAlert?
    private var reportedConflicts: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        search.onFinish = { [weak self] query in self?.coordinator.finishSearch(query) }
        shortcuts = ShortcutController { [weak self] command in
            guard let self else { return }
            if !AXIsProcessTrusted() {
                coordinator.handle(.escape)
                showPermissionAlert()
                return
            }
            coordinator.handle(command)
        }
        setMode(.normal)
        if !AXIsProcessTrusted() { showPermissionAlert() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcuts?.stop()
        guides.hide()
        search.hide()
    }

    func setMode(_ mode: Mode) {
        let conflicts = shortcuts?.setMode(mode) ?? []
        let newConflicts = Set(conflicts).subtracting(reportedConflicts)
        let shouldExitMode = !conflicts.isEmpty && (mode == .command || mode == .quickSwitch)
        guard shouldExitMode || !newConflicts.isEmpty else { return }
        reportedConflicts.formUnion(newConflicts)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if shouldExitMode { coordinator.handle(.escape) }
            guard !newConflicts.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Some Vimdow shortcuts are unavailable"
            alert.informativeText = "Another app or macOS may be using: \(newConflicts.sorted().joined(separator: ", ")). Close the other Vimdow instance or resolve the conflict, then restart Vimdow."
            alert.runModal()
        }
    }

    func showGuides(_ windows: [WindowInfo]) { guides.show(windows) }
    func hideGuides() { guides.hide() }
    func showSearch() { search.show() }
    func hideSearch() { search.hide() }
    func quit() { NSApp.terminate(nil) }

    func showFailure(_ error: any Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        if error as? WindowFailure == .permissionDenied { showPermissionAlert() }
        else { NSSound.beep() }
    }

    private func showPermissionAlert() {
        guard permissionAlert == nil else { return }
        logger.notice("Accessibility permission missing for \(Bundle.main.bundleURL.path, privacy: .public), PID \(ProcessInfo.processInfo.processIdentifier)")
        // Explicit checks and a Retry button avoid terminating the app or repeatedly prompting macOS.
        let alert = NSAlert()
        permissionAlert = alert
        alert.messageText = "Allow Vimdow to control windows"
        alert.informativeText = "Enable VimdowManager in System Settings → Privacy & Security → Accessibility. If it is already enabled after an update, remove its entry with the minus button, add this app again, and restart Vimdow.\n\nApp: \(Bundle.main.bundleURL.path)\n\nChoose Retry to check again, or press Control–Option–A after closing this dialog."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        permissionAlert = nil
        if response == .alertFirstButtonReturn {
            // This dialog already explains the request; opening Settings must not also
            // ask macOS to display a second accessibility prompt.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn && !AXIsProcessTrusted() {
            Task { @MainActor [weak self] in self?.showPermissionAlert() }
        } else if response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1 {
            NSApp.terminate(nil)
        }
    }

    private func installMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Vimdow")
        applicationMenu.addItem(withTitle: "About Vimdow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Vimdow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
