import ADOCore
import AppKit
import ServiceManagement
import UserNotifications

/// Notifications système. Inactif hors bundle `.app` (ex. `swift run`) : UNUserNotificationCenter l'exige.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (URL) -> Void = { _ in }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        guard let center else { return }
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
    }

    func post(_ content: NotificationContent) {
        guard let center else { return }
        let note = UNMutableNotificationContent()
        note.title = content.title
        if let subtitle = content.subtitle { note.subtitle = subtitle }
        note.body = content.body
        note.threadIdentifier = content.threadID
        note.userInfo = ["url": content.url.absoluteString]
        note.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: note, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo["url"] as? String,
            let url = URL(string: text)
        else { return }
        await MainActor.run { onOpen(url) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        if enabled, service.status != .enabled {
            try? service.register()
        } else if !enabled, service.status == .enabled {
            try? service.unregister()
        }
    }

    /// Raison pour laquelle l'app ne se lancera pas à l'ouverture de session, si activé mais inopérant.
    static var issue: String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        switch SMAppService.mainApp.status {
        case .enabled: return nil
        case .requiresApproval: return "Needs approval in System Settings › Login Items."
        default: return "Couldn't register ADO Notifier as a login item."
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Réveil du Mac → refresh immédiat.
@MainActor
final class WakeObserver {
    static let shared = WakeObserver()
    var onWake: () -> Void = {}

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WakeObserver.shared.onWake() }
        }
    }
}
