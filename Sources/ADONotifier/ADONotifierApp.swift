import ADOCore
import SwiftUI

@main
struct ADONotifierApp: App {
    @State private var model = AppModel()

    init() {
        // Info-bulles (titres complets) : délai système ~1 s trop long pour un survol de liste.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
        } label: {
            MenuBarLabel(icon: model.panel.icon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }

        Window("Set Up ADO Notifier", id: SetupView.windowID) {
            SetupView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// Icône template : glyphe + variante (compteur, `!`, cloche barrée, estompé).
struct MenuBarLabel: View {
    let icon: MenuBarIcon

    var body: some View {
        switch icon {
        case .notConfigured:
            Image(nsImage: Self.glyph(alpha: 0.45))
                .accessibilityLabel("ADO Notifier, not configured")
        case .muted:
            Image(nsImage: Self.glyph(suffix: "bell.slash"))
                .accessibilityLabel("ADO Notifier, notifications muted")
        case .error:
            Image(nsImage: Self.glyph(suffix: "exclamationmark"))
                .accessibilityLabel("ADO Notifier, sync error")
        case .activity(let count):
            HStack(spacing: 3) {
                Image(nsImage: Self.glyph())
                Text("\(count)")
            }
            .accessibilityLabel("ADO Notifier, \(count) items need attention")
        case .normal:
            Image(nsImage: Self.glyph())
                .accessibilityLabel("ADO Notifier")
        }
    }

    static func glyph(suffix: String? = nil, alpha: CGFloat = 1) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)!
            .withSymbolConfiguration(config)!
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let badge = suffix.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(badgeConfig)
        }
        let width = base.size.width + (badge.map { $0.size.width + 1 } ?? 0)
        let height = max(base.size.height, badge?.size.height ?? 0)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            base.draw(
                in: NSRect(x: 0, y: (height - base.size.height) / 2, width: base.size.width, height: base.size.height),
                from: .zero, operation: .sourceOver, fraction: alpha)
            if let badge {
                badge.draw(
                    in: NSRect(x: base.size.width + 1, y: 0, width: badge.size.width, height: badge.size.height),
                    from: .zero, operation: .sourceOver, fraction: alpha)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension View {
    /// Ouvre une fenêtre d'une app sans Dock au premier plan.
    func activatingApp() -> some View {
        onAppear { NSApp.activate() }
    }
}
