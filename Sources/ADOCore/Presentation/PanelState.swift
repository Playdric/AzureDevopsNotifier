import Foundation

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case failed(ADOError)
}

public enum MenuBarIcon: Equatable, Sendable {
    case notConfigured
    case muted
    case error
    case activity(Int)
    case normal
}

public enum Banner: Equatable, Sendable {
    case networkError(lastSync: Date?)
    case tokenExpired(lastSync: Date?)
    case throttled(lastSync: Date?)
    case muted(until: Date?)
}

public struct VoteCount: Equatable, Sendable {
    public var vote: Vote
    public var count: Int
}

public struct PRRow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    /// Titre complet sans nettoyage (info-bulle, AC36).
    public var originalTitle: String
    public var repository: String
    public var author: String
    public var created: Date
    public var isDraft: Bool
    public var isNew: Bool
    public var votes: [VoteCount]
    /// Pipelines de build validation, ordre ADO ; vide si aucun ou statut inconnu.
    public var pipelines: [PipelineCheck] = []
    /// My PRs uniquement (UC5).
    public var isReady = false
    public var url: URL
}

extension PRRow {
    private enum CIState { case failed, optionalFailed, pending, passed }

    private var ciState: CIState? {
        guard !pipelines.isEmpty else { return nil }
        let failed = pipelines.filter { $0.status == .failed }
        let pending = pipelines.contains { $0.status.isPending }
        if failed.contains(where: \.isRequired) { return .failed }
        if !failed.isEmpty && !pending { return .optionalFailed }
        return pending ? .pending : .passed
    }

    /// En-tête du détail CI (popover au survol des pastilles).
    public var ciHeader: String? {
        guard let state = ciState else { return nil }
        let total = pipelines.count
        return switch state {
        case .failed: "CI · \(pipelines.count { $0.status == .failed }) of \(total) failed"
        case .optionalFailed: "CI · optional pipeline failed"
        case .pending: "CI · \(pipelines.count { $0.status.isPending }) of \(total) pending"
        case .passed: "CI · all \(total) succeeded"
        }
    }

    public var ciAccessibilityLabel: String? {
        guard let state = ciState else { return nil }
        let label =
            switch state {
            case .failed: "CI: \(pipelines.count { $0.status == .failed }) of \(pipelines.count) failed"
            case .optionalFailed: "CI: optional pipeline failed"
            case .pending: "CI: running"
            case .passed: "CI: succeeded"
            }
        return label + (isReady ? ", ready to merge" : "")
    }
}

public struct WIRow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var originalTitle: String
    public var typeName: String
    public var typeColor: String?
    public var project: String
    /// État courant, toujours affiché même s'il est masqué (AC22).
    public var state: String
    public var category: StateCategory?
    public var stateOptions: [StateDef]
    public var isNew: Bool
    public var url: URL
}

public struct PanelSection<Row: Equatable & Sendable>: Equatable, Sendable {
    public var rows: [Row]
    public var total: Int
    /// Lien « Show all N … in browser » quand `total` dépasse le plafond.
    public var overflowURL: URL?
    /// Éléments masqués par les filtres d'affichage (drafts, états).
    public var hiddenCount = 0
}

/// Ce que le panneau et l'icône affichent, dérivé de l'état de l'app.
public struct PanelState: Equatable, Sendable {
    public static let maxRows = 50

    public var isConfigured: Bool
    public var icon: MenuBarIcon
    public var banners: [Banner]
    /// Premier chargement : aucune donnée encore (skeleton).
    public var isLoading: Bool
    public var isSyncing: Bool
    public var lastSync: Date?
    public var toReview: PanelSection<PRRow>
    public var myPRs: PanelSection<PRRow>
    public var workItems: PanelSection<WIRow>

    public static func seenKey(pr id: Int) -> String { "pr:\(id)" }
    public static func seenKey(wi id: Int) -> String { "wi:\(id)" }

    public static func make(
        prefs: Preferences, snapshot: Snapshot?, status: SyncStatus, seen: Set<String>, now: Date
    ) -> PanelState {
        let empty = PanelState(
            isConfigured: false, icon: .notConfigured, banners: [], isLoading: false, isSyncing: false,
            lastSync: nil, toReview: PanelSection(rows: [], total: 0), myPRs: PanelSection(rows: [], total: 0),
            workItems: PanelSection(rows: [], total: 0))
        guard prefs.isConfigured, let org = prefs.orgURL else { return empty }
        let links = WebLinks(org: org)

        func prRow(_ pr: PullRequest, mine: Bool) -> PRRow {
            let checks = snapshot?.checks[pr.id]
            let counts = Dictionary(grouping: pr.reviewers.filter { $0.identity.id != prefs.me?.id }, by: \.vote)
            let votes = Vote.allCases.compactMap { vote in
                counts[vote].map { VoteCount(vote: vote, count: $0.count) }
            }
            return PRRow(
                id: pr.id, title: TitleCleaner.clean(pr.title, settings: prefs.tags), originalTitle: pr.title,
                repository: pr.repositoryName, author: pr.author.displayName, created: pr.creationDate,
                isDraft: pr.isDraft, isNew: !seen.contains(seenKey(pr: pr.id)), votes: votes,
                pipelines: checks?.pipelines ?? [], isReady: mine && pr.isReady(checks),
                url: links.pullRequest(pr))
        }
        func wiRow(_ wi: WorkItem, types: TypeCatalog) -> WIRow {
            WIRow(
                id: wi.id, title: TitleCleaner.clean(wi.title, settings: prefs.tags), originalTitle: wi.title,
                typeName: wi.typeName, typeColor: StateMenu.type(of: wi, in: types)?.color, project: wi.projectName,
                state: wi.state, category: StateMenu.category(of: wi, in: types),
                stateOptions: StateMenu.options(for: wi, types: types, hidden: prefs.hiddenStates),
                isNew: !seen.contains(seenKey(wi: wi.id)), url: links.workItem(wi))
        }
        func section<T, Row>(_ all: [T], visible: [T], overflow: URL, _ map: (T) -> Row) -> PanelSection<Row> {
            PanelSection(
                rows: visible.prefix(maxRows).map(map), total: visible.count,
                overflowURL: visible.count > maxRows ? overflow : nil, hiddenCount: all.count - visible.count)
        }

        // Filtres d'affichage seulement : le snapshot (et donc les notifications) reste complet.
        let types = snapshot?.types ?? [:]
        let allReview = snapshot?.toReview ?? []
        let allMine = snapshot?.myPRs ?? []
        let allWIs = snapshot?.workItems ?? []
        let display = DisplayFilter(prefs: prefs)
        let visibleReview = allReview.filter { !display.hides(review: $0) }
        let visibleMine = allMine.filter { !display.hides(mine: $0) }
        let visibleWIs = allWIs.filter { !display.hides($0) }

        let toReview = section(allReview, visible: visibleReview, overflow: links.allPullRequests) {
            prRow($0, mine: false)
        }
        let myPRs = section(allMine, visible: visibleMine, overflow: links.allPullRequests) { prRow($0, mine: true) }
        let workItems = section(
            allWIs, visible: visibleWIs,
            overflow: links.assignedWorkItems(project: prefs.projects.first?.name ?? "")
        ) { wiRow($0, types: types) }

        let lastSync = snapshot?.fetchedAt
        let muted = prefs.mute.isActive(at: now)
        var banners: [Banner] = []
        if case .failed(let error) = status {
            switch error {
            case .unauthorized: banners.append(.tokenExpired(lastSync: lastSync))
            case .rateLimited: banners.append(.throttled(lastSync: lastSync))
            default: banners.append(.networkError(lastSync: lastSync))
            }
        }
        if muted {
            if case .until(let end) = prefs.mute {
                banners.append(.muted(until: end))
            } else {
                banners.append(.muted(until: nil))
            }
        }

        let unseenWIs = visibleWIs.filter { !seen.contains(seenKey(wi: $0.id)) }.count
        let activity = visibleReview.count + unseenWIs
        let icon: MenuBarIcon
        if muted {
            icon = .muted
        } else if case .failed = status {
            icon = .error
        } else {
            icon = activity > 0 ? .activity(activity) : .normal
        }

        var failed = false
        if case .failed = status { failed = true }
        return PanelState(
            isConfigured: true, icon: icon, banners: banners, isLoading: snapshot == nil && !failed,
            isSyncing: status == .syncing, lastSync: lastSync, toReview: toReview, myPRs: myPRs, workItems: workItems)
    }
}
