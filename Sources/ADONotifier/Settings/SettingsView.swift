import ADOCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Account", systemImage: "person.crop.circle") { AccountSettingsView() }
            Tab("Projects", systemImage: "folder") { ProjectsSettingsView() }
            Tab("Titles", systemImage: "textformat") { TitlesSettingsView() }
            Tab("States", systemImage: "list.bullet") { StatesSettingsView() }
        }
        .frame(width: 480)
        .onAppear { model.requestTypesRefresh() }
        .activatingApp()
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(
                    "Refresh every",
                    selection: Binding(get: { model.prefs.refreshMinutes }, set: model.setRefreshMinutes)
                ) {
                    ForEach(Preferences.refreshChoices, id: \.self) { Text("\($0) minute\($0 > 1 ? "s" : "")").tag($0) }
                }
                Toggle(
                    "Launch at login", isOn: Binding(get: { model.prefs.launchAtLogin }, set: model.setLaunchAtLogin))
                if model.prefs.launchAtLogin, let issue = LaunchAtLogin.issue {
                    LabeledContent {
                        Button("Open Login Items…") { LaunchAtLogin.openSystemSettings() }
                    } label: {
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Picker(
                    "Panel width",
                    selection: Binding(get: { model.prefs.panelWidth }, set: { model.prefs.panelWidth = $0 })
                ) {
                    ForEach(PanelWidth.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle(isOn: Binding(get: { model.prefs.wrapTitles }, set: { model.prefs.wrapTitles = $0 })) {
                    Text("Wrap titles")
                    Text("Show long titles on up to two lines.")
                }
                Toggle(
                    "Hide drafts in To Review",
                    isOn: Binding(get: { model.prefs.hideDraftsToReview }, set: { model.prefs.hideDraftsToReview = $0 })
                )
                Toggle(
                    "Hide drafts in My PRs",
                    isOn: Binding(get: { model.prefs.hideDraftsMine }, set: { model.prefs.hideDraftsMine = $0 }))
                Toggle(
                    isOn: Binding(get: { model.prefs.notifyHiddenItems }, set: { model.prefs.notifyHiddenItems = $0 })
                ) {
                    Text("Notify for hidden items")
                    Text("Drafts and work items hidden by your filters.")
                }
            } header: {
                Text("Panel")
            }
            Section("Notifications") {
                if model.notifications.authorization == .denied {
                    LabeledContent {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    } label: {
                        Label("Notifications are turned off for ADO Notifier", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text("Allow them in System Settings to get alerts.")
                    }
                } else {
                    Label("Notifications allowed", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
                LabeledContent("Mute") {
                    if case .until(let end) = model.prefs.mute, model.prefs.mute.isActive(at: model.now) {
                        Text("Muted until \(end.formatted(Formats.muteEnd))")
                    } else if model.prefs.mute == .indefinitely {
                        Text("Muted until you turn it back on")
                    } else {
                        Text("Not muted · use the bell in the menu")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.notifications.refreshAuthorization() }
    }
}

struct AccountSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var orgText = ""
    @State private var pat = ""
    @State private var saving = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                TextField("Organization URL", text: $orgText)
                SecureField("Personal access token", text: $pat, prompt: Text("Leave empty to keep the current token"))
                LabeledContent("Signed in as", value: model.prefs.me?.displayName ?? "—")
            } footer: {
                Text("The token is stored in your keychain.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if saving {
                    ProgressView().controlSize(.small)
                    Text("Checking token…")
                } else if let message {
                    Text(message).foregroundStyle(failed ? .red : .green)
                }
                Spacer()
                Button("Save") { Task { await save() } }.disabled(saving)
            }
        }
        .formStyle(.grouped)
        .onAppear { orgText = model.prefs.orgURL?.description ?? "" }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.updateAccount(orgText: orgText, pat: pat)
            pat = ""
            failed = false
            message = "Saved"
        } catch {
            failed = true
            message = (error as? ADOError)?.message ?? "Couldn't save the token to the keychain."
        }
    }
}

struct ProjectsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var projects: [Project] = []
    @State private var selected: Set<String> = []
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ProjectChecklist(
                    projects: projects, selected: $selected, warnings: model.snapshot?.inaccessibleProjects ?? [])
            } footer: {
                Text(error ?? "At least one project required. Changes apply on next refresh.")
                    .font(.caption)
                    .foregroundStyle(error == nil ? .secondary : Color.red)
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
        .task { await load() }
        // Appliqué 1 s après le dernier clic : une seule relance de la synchro pour plusieurs cases.
        .task(id: selected) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { apply() }
        }
        .onDisappear { apply() }
    }

    private func apply() {
        guard !projects.isEmpty else { return }
        guard !selected.isEmpty else {
            error = "Select at least one project."
            return
        }
        error = nil
        model.setProjects(projects.filter { selected.contains($0.id) })
    }

    private func load() async {
        selected = Set(model.prefs.projects.map(\.id))
        let available = (try? await model.availableProjects()) ?? []
        // Projets suivis absents de l'org gardés pour afficher l'avertissement.
        projects = available + model.prefs.projects.filter { p in !available.contains { $0.id == p.id } }
    }
}

struct TitlesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        let tags = model.prefs.tags
        let entries = TagCatalog.entries(titles: model.currentTitles, settings: tags).filter {
            search.isEmpty || $0.display.localizedCaseInsensitiveContains(search)
        }
        Form {
            Section {
                Toggle(isOn: Binding(get: { tags.hideAll }, set: { model.prefs.tags.hideAll = $0 })) {
                    Text("Hide all tags")
                    Text("Includes tags not listed yet.")
                }
            } header: {
                Text(
                    "Hide [bracketed] tags from pull request and work item titles in the menu and in notifications. Hover a row to see its full title."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("Detected tags") {
                TextField("Search", text: $search, prompt: Text("Search"))
                if entries.isEmpty {
                    Text("No matching tag.").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Toggle(
                        isOn: Binding(
                            get: { entry.isHidden },
                            set: { on in
                                if on {
                                    model.prefs.tags.hidden.insert(entry.key)
                                } else {
                                    model.prefs.tags.hidden.remove(entry.key)
                                }
                            }
                        )
                    ) {
                        HStack {
                            Text("[\(entry.display)]")
                            Spacer()
                            Text(
                                entry.count > 0
                                    ? "\(entry.count) title\(entry.count > 1 ? "s" : "")" : "Not seen recently"
                            )
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(tags.hideAll)
                }
            }
            if let example = model.currentTitles.first(where: { !TitleCleaner.tags(in: $0).isEmpty }) {
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example).strikethrough().foregroundStyle(.secondary).font(.caption)
                        Text(TitleCleaner.clean(example, settings: tags))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }
}

struct StatesSettingsView: View {
    @Environment(AppModel.self) private var model

    private enum Column { case menu, list }

    var body: some View {
        let entries = StateCatalog.entries(model.snapshot?.types ?? [:])
        Form {
            Section {
                if entries.isEmpty {
                    Text("States appear after the first sync.").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("State")
                        Spacer()
                        columnHeader("Menu", .menu, names: entries.map(\.name))
                        columnHeader("List", .list, names: entries.map(\.name))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        HStack(spacing: 4) {
                            CategoryDot(category: entry.categories.first)
                            Text(entry.categories.map(\.label).joined(separator: ", "))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        checkbox(entry.name, .menu)
                        checkbox(entry.name, .list)
                    }
                }
            } header: {
                Text(
                    "Menu: state offered in status menus. List: work items in this state shown in the panel. A work item's current state is always shown."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }

    private func hidden(_ column: Column) -> Set<String> {
        column == .menu ? model.prefs.hiddenStates : model.prefs.listHiddenStates
    }

    private func setHidden(_ column: Column, _ value: Set<String>) {
        if column == .menu { model.prefs.hiddenStates = value } else { model.prefs.listHiddenStates = value }
    }

    private func checkbox(_ name: String, _ column: Column) -> some View {
        Toggle(
            isOn: Binding(
                get: { !hidden(column).contains(name) },
                set: { visible in
                    var set = hidden(column)
                    if visible { set.remove(name) } else { set.insert(name) }
                    setHidden(column, set)
                }
            )
        ) {
            Text(column == .menu ? "\(name) in status menu" : "\(name) in list")
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(width: 70)
    }

    /// Titre de colonne + Check All / Uncheck All (AC41).
    private func columnHeader(_ title: String, _ column: Column, names: [String]) -> some View {
        VStack(spacing: 2) {
            Text(title)
            HStack(spacing: 4) {
                Button("All") { setHidden(column, hidden(column).subtracting(names)) }
                    .accessibilityLabel("Check all in \(title)")
                Button("None") { setHidden(column, hidden(column).union(names)) }
                    .accessibilityLabel("Uncheck all in \(title)")
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .frame(width: 70)
    }
}
