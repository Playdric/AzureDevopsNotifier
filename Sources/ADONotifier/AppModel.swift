import ADOCore
import AppKit
import Observation

/// État de l'app : réglages, dernier snapshot, synchro, actions du panneau et des réglages.
@MainActor
@Observable
final class AppModel {
    struct RowError: Equatable {
        var targetState: String
        var message: String
    }

    var prefs: Preferences {
        didSet { if prefs != oldValue { store.save(prefs) } }
    }
    private(set) var snapshot: Snapshot?
    private(set) var status: SyncStatus = .idle
    /// Éléments déjà vus ; tout ce qui est hors de cet ensemble porte le point « nouveau ».
    private(set) var seen: Set<String> = []
    private(set) var pendingStates: [Int: String] = [:]
    private(set) var rowErrors: [Int: RowError] = [:]
    /// Horloge de rafraîchissement de la sourdine et des libellés relatifs.
    private(set) var now = Date.now

    let notifications = NotificationService()
    private let store: PreferencesStore
    private let secrets: SecretStore
    private var sync: SyncService?
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var client: ADOClient?

    init(store: PreferencesStore = PreferencesStore(), secrets: SecretStore = KeychainStore()) {
        self.store = store
        self.secrets = secrets
        prefs = store.load()
        notifications.onOpen = { url in NSWorkspace.shared.open(url) }
        WakeObserver.shared.onWake = { [weak self] in self?.refresh() }
        startTicking()
        if prefs.isConfigured {
            notifications.requestAuthorization()
            startPolling()
        }
    }

    var panel: PanelState {
        PanelState.make(prefs: prefs, snapshot: snapshot, status: status, seen: seen, now: now)
    }

    var links: WebLinks? { prefs.orgURL.map(WebLinks.init) }

    // MARK: - Synchro

    private func startPolling() {
        pollTask?.cancel()
        snapshot = nil
        seen = []
        guard let org = prefs.orgURL, let me = prefs.me, let pat = try? secrets.read(account: org.description) else {
            status = .failed(.unauthorized)
            return
        }
        let client = ADOClient(org: org, pat: pat)
        let fetcher = SnapshotFetcher(client: client, me: me, projects: prefs.projects.map(\.name))
        let sync = SyncService(interval: prefs.refreshInterval) { previous, refreshTypes in
            try await fetcher.fetch(previous: previous, refreshTypes: refreshTypes)
        }
        self.client = client
        self.sync = sync
        status = .syncing
        pollTask = Task {
            await sync.run { [weak self] outcome in await self?.handle(outcome, from: sync) }
        }
    }

    private func handle(_ outcome: CycleOutcome, from origin: SyncService) {
        // Résultat d'une synchro remplacée (changement de projets / compte) : ignoré.
        guard origin === sync else { return }
        now = .now
        prefs.mute = prefs.mute.normalized(at: now)
        switch outcome {
        case .baseline(let snapshot):
            apply(snapshot)
            // Baseline : tout l'existant compte comme vu (pas de rafale de points bleus).
            seen = Self.keys(snapshot)
        case .updated(let snapshot, let events):
            apply(snapshot)
            guard let links else { return }
            for event in NotificationGate.filter(events, prefs: prefs, now: now) {
                notifications.post(NotificationContent.make(event, tags: prefs.tags, links: links))
            }
        case .failed(let error, _):
            status = .failed(error)
        }
    }

    private func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        status = .idle
        TagCatalog.merge(Self.titles(snapshot), into: &prefs.tags)
    }

    func refresh() {
        guard let sync else { return }
        if snapshot == nil || status != .idle { status = .syncing }
        Task {
            if let outcome = await sync.cycle() { handle(outcome, from: sync) }
        }
    }

    func panelClosed() {
        if let snapshot { seen.formUnion(Self.keys(snapshot)) }
    }

    func requestTypesRefresh() {
        guard let sync else { return }
        Task { await sync.requestTypesRefresh() }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.now = .now
                self.prefs.mute = self.prefs.mute.normalized(at: self.now)
            }
        }
    }

    private static func keys(_ snapshot: Snapshot) -> Set<String> {
        Set(
            snapshot.toReview.map { PanelState.seenKey(pr: $0.id) }
                + snapshot.myPRs.map { PanelState.seenKey(pr: $0.id) }
                + snapshot.workItems.map { PanelState.seenKey(wi: $0.id) })
    }

    static func titles(_ snapshot: Snapshot) -> [String] {
        snapshot.toReview.map(\.title) + snapshot.myPRs.map(\.title) + snapshot.workItems.map(\.title)
    }

    var currentTitles: [String] { snapshot.map(Self.titles) ?? [] }

    // MARK: - Actions panneau

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func changeState(workItemID: Int, to state: String) {
        guard let client else { return }
        rowErrors[workItemID] = nil
        pendingStates[workItemID] = state
        Task {
            defer { pendingStates[workItemID] = nil }
            do {
                let updated = try await client.updateState(workItemID: workItemID, to: state)
                if let index = snapshot?.workItems.firstIndex(where: { $0.id == workItemID }) {
                    snapshot?.workItems[index].state = updated.state
                }
            } catch {
                let message = (error as? ADOError)?.message ?? error.localizedDescription
                rowErrors[workItemID] = RowError(targetState: state, message: message)
            }
        }
    }

    func dismissRowError(_ workItemID: Int) {
        rowErrors[workItemID] = nil
    }

    func mute(_ preset: MutePreset) throws {
        prefs.mute = try preset.state(now: .now)
        now = .now
    }

    func unmute() {
        prefs.mute = .off
    }

    func toggleSection(_ key: String) {
        if prefs.collapsedSections.contains(key) {
            prefs.collapsedSections.remove(key)
        } else {
            prefs.collapsedSections.insert(key)
        }
    }

    // MARK: - Configuration

    struct Connection {
        var org: OrgURL
        var pat: String
        var me: Identity
        var projects: [Project]
    }

    /// Valide org + PAT (UC1 étape 3-4). Rien n'est enregistré ici.
    func connect(orgText: String, pat: String) async throws -> Connection {
        guard let org = OrgURL(orgText) else {
            throw ADOError.server(status: 0, message: "Enter a URL like https://dev.azure.com/your-org.")
        }
        let token = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ADOError.server(status: 0, message: "Enter a personal access token.") }
        let client = ADOClient(org: org, pat: token)
        let me = try await client.connectionData()
        let projects = try await client.projects().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Connection(org: org, pat: token, me: me, projects: projects)
    }

    func completeSetup(_ connection: Connection, projects: [Project], launchAtLogin: Bool) throws {
        try save(connection)
        prefs.projects = projects
        prefs.launchAtLogin = launchAtLogin
        LaunchAtLogin.set(launchAtLogin)
        notifications.requestAuthorization()
        startPolling()
    }

    /// Settings › Account : PAT vide → token actuel conservé.
    func updateAccount(orgText: String, pat: String) async throws {
        var token = pat
        if token.isEmpty, let org = prefs.orgURL { token = (try? secrets.read(account: org.description)) ?? "" }
        let connection = try await connect(orgText: orgText, pat: token)
        if let old = prefs.orgURL, old != connection.org { try? secrets.delete(account: old.description) }
        try save(connection)
        startPolling()
    }

    private func save(_ connection: Connection) throws {
        try secrets.write(connection.pat, account: connection.org.description)
        prefs.orgURL = connection.org
        prefs.me = connection.me
    }

    func availableProjects() async throws -> [Project] {
        guard let client else { return prefs.projects }
        return try await client.projects().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func setProjects(_ projects: [Project]) {
        guard !projects.isEmpty, projects != prefs.projects else { return }
        prefs.projects = projects
        // Nouveau périmètre → nouvelle baseline, pas de notification pour l'existant.
        startPolling()
    }

    func setRefreshMinutes(_ minutes: Int) {
        prefs.refreshMinutes = minutes
        let interval = prefs.refreshInterval
        if let sync { Task { await sync.setInterval(interval) } }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        prefs.launchAtLogin = enabled
        LaunchAtLogin.set(enabled)
    }
}
