import ADOCore
import SwiftUI

enum Formats {
    static let clock: Date.FormatStyle = .dateTime.hour().minute().locale(Locale(identifier: "en_GB"))
    static let muteEnd: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        .locale(Locale(identifier: "en_US"))
}

struct StatusBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let banner: Banner

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(isError ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            switch banner {
            case .networkError: Button("Retry") { model.refresh() }
            case .throttled: EmptyView()
            case .tokenExpired:
                Button("Update…") { navigation.openSettings() }
            case .muted: Button("Unmute") { model.unmute() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isError ? AnyShapeStyle(.red.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: .rect(cornerRadius: 10)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var isError: Bool {
        if case .muted = banner { false } else { true }
    }

    private var symbol: String {
        switch banner {
        case .networkError: "exclamationmark.triangle"
        case .tokenExpired: "key"
        case .throttled: "hourglass"
        case .muted: "bell.slash"
        }
    }

    private var title: String {
        switch banner {
        case .networkError: "Can't reach Azure DevOps"
        case .tokenExpired: "Personal access token expired"
        case .throttled: "Azure DevOps is throttling requests"
        case .muted: "Notifications muted"
        }
    }

    private var detail: String {
        switch banner {
        case .networkError(let last):
            (last.map { "Showing data from \($0.formatted(Formats.clock)). " } ?? "") + "Retrying automatically."
        case .throttled(let last):
            (last.map { "Showing data from \($0.formatted(Formats.clock)). " } ?? "") + "Retrying at the next refresh."
        case .tokenExpired(let last):
            (last.map { "Showing data from \($0.formatted(Formats.clock)). " } ?? "")
                + "Update your token to resume syncing."
        case .muted(let until):
            until.map { "Until \($0.formatted(Formats.muteEnd))" } ?? "Until you turn them back on"
        }
    }
}

struct PanelFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let panel: PanelState
    @State private var pickingDate = false

    var body: some View {
        HStack(spacing: 2) {
            Group {
                if panel.isSyncing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Syncing…")
                    }
                } else {
                    Text(syncLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            Spacer()

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")

            muteMenu

            Menu {
                Button("Settings…") { navigation.openSettings() }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit ADO Notifier") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var syncLabel: String {
        if case .failed = model.status, let last = panel.lastSync {
            return "Last synced \(last.formatted(Formats.clock))"
        }
        guard let last = panel.lastSync else { return "" }
        let minutes = Int(model.now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Updated just now" : "Updated \(minutes) min ago"
    }

    private var muted: Bool { model.prefs.mute.isActive(at: model.now) }

    private var muteMenu: some View {
        Menu {
            if muted {
                Button("Unmute") { model.unmute() }
            } else {
                Section("Mute Notifications") {
                    Button("For 1 Hour") { try? model.mute(.oneHour) }
                    Button("Until Tomorrow, 9:00") { try? model.mute(.untilTomorrowMorning) }
                    Button("Until Date…") { pickingDate = true }
                    Button("Until I Turn It Back On") { try? model.mute(.indefinitely) }
                }
            }
        } label: {
            Image(systemName: muted ? "bell.slash" : "bell")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(muted ? "Notifications muted" : "Mute notifications")
        .accessibilityLabel("Mute notifications")
        .popover(isPresented: $pickingDate, arrowEdge: .top) {
            MuteDatePicker { pickingDate = false }
        }
    }
}

struct MuteDatePicker: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void
    @State private var date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)!
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Mute until", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Mute") {
                    do {
                        try model.mute(.until(date))
                        done()
                    } catch {
                        self.error = "Choose a date in the future."
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
