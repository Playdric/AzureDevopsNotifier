import ADOCore
import SwiftUI

/// Configuration initiale en 2 étapes : Connect → Projects (UC1).
struct SetupView: View {
    static let windowID = "setup"

    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var orgText = "https://dev.azure.com/"
    @State private var pat = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var connection: AppModel.Connection?
    @State private var selected: Set<String> = []
    @State private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("1 Connect").fontWeight(connection == nil ? .semibold : .regular)
                Image(systemName: "chevron.right").font(.caption2)
                Text("2 Projects").fontWeight(connection == nil ? .regular : .semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)

            if let connection {
                projectsStep(connection)
            } else {
                connectStep
            }
        }
        .padding(20)
        .frame(width: 480)
        .activatingApp()
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField("Organization URL", text: $orgText, prompt: Text("https://dev.azure.com/your-org"))
                SecureField("Personal access token", text: $pat, prompt: Text("Paste token"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scopes: Code (Read), Work Items (Read & Write), Project and Team (Read).")
                    if let org = OrgURL(orgText) {
                        Link("Create a token…", destination: org.base.appending(path: "_usersSettings/tokens"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                status
                Spacer()
                Button("Connect") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if connecting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking token…")
            }
            .font(.callout)
        } else if let error {
            Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func projectsStep(_ connection: AppModel.Connection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed in as **\(connection.me.displayName)** · \(connection.org.name)").font(.callout)
            Form {
                Section("Projects to follow") {
                    ProjectChecklist(projects: connection.projects, selected: $selected)
                }
                Section {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                }
            }
            .formStyle(.grouped)
            .frame(height: 320)

            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Spacer()
                Button("Back") {
                    self.connection = nil
                    error = nil
                }
                Button("Finish") { finish(connection) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func connect() async {
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            connection = try await model.connect(orgText: orgText, pat: pat)
        } catch {
            self.error = (error as? ADOError)?.message ?? error.localizedDescription
        }
    }

    private func finish(_ connection: AppModel.Connection) {
        let projects = connection.projects.filter { selected.contains($0.id) }
        guard !projects.isEmpty else {
            error = "Select at least one project."
            return
        }
        do {
            try model.completeSetup(connection, projects: projects, launchAtLogin: launchAtLogin)
            pat = ""
            dismissWindow(id: Self.windowID)
        } catch {
            self.error = "Couldn't save the token to the keychain."
        }
    }
}

struct ProjectChecklist: View {
    let projects: [Project]
    @Binding var selected: Set<String>
    var warnings: [String] = []

    var body: some View {
        ForEach(projects) { project in
            Toggle(
                isOn: Binding(
                    get: { selected.contains(project.id) },
                    set: { on in if on { selected.insert(project.id) } else { selected.remove(project.id) } }
                )
            ) {
                Text(project.name)
                if warnings.contains(project.name) {
                    Text("No longer accessible — ignored").foregroundStyle(.red)
                }
            }
            .toggleStyle(.checkbox)
        }
    }
}
