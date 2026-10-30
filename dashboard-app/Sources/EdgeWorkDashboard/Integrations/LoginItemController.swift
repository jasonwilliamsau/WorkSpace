import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled }

    var statusMessage: String {
        switch status {
        case .enabled: "EDGE Work Dashboard will open when you log in."
        case .requiresApproval: "Approval is required in System Settings → Login Items."
        case .notRegistered: "The dashboard will not open automatically."
        case .notFound: "Launch at Login is available from the installed application bundle."
        @unknown default: "Login-item status is unavailable."
        }
    }

    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
