import ServiceManagement

/// Whether macOS opens Vimdow at login. The system owns this state, so Vimdow keeps no copy;
/// the user can also change it in System Settings → General → Login Items.
protocol LoginItem {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

extension SMAppService: LoginItem {
    func openSystemSettings() { Self.openSystemSettingsLoginItems() }
}
