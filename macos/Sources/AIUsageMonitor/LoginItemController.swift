import Foundation
import ServiceManagement

/// Launch-at-login control backed by `SMAppService` (macOS 13+), the Mac
/// counterpart of the Windows Startup-folder toggle.
enum LoginItemController {
    static func register() throws {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled, .requiresApproval:
            return
        default:
            try service.register()
        }
    }

    static func unregister() throws {
        let service = SMAppService.mainApp
        guard service.status != .notRegistered else { return }
        try service.unregister()
    }

    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}
