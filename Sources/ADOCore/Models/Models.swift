import Foundation

public struct Identity: Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct Project: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum Vote: Int, Codable, Hashable, Sendable, CaseIterable {
    case approved = 10
    case approvedWithSuggestions = 5
    case none = 0
    case waitingForAuthor = -5
    case rejected = -10

    public var label: String {
        switch self {
        case .approved: "Approved"
        case .approvedWithSuggestions: "Approved with Suggestions"
        case .none: "No Vote"
        case .waitingForAuthor: "Waiting for Author"
        case .rejected: "Rejected"
        }
    }
}

public struct Reviewer: Codable, Hashable, Sendable {
    public var identity: Identity
    public var vote: Vote
    public var isContainer: Bool

    public init(identity: Identity, vote: Vote, isContainer: Bool = false) {
        self.identity = identity
        self.vote = vote
        self.isContainer = isContainer
    }
}

public struct PullRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var projectID: String
    public var projectName: String
    public var repositoryName: String
    public var author: Identity
    public var creationDate: Date
    public var isDraft: Bool
    public var reviewers: [Reviewer]
    /// Conflit ou échec de fusion : ADO bloque la complétion.
    public var hasMergeConflict: Bool

    public init(
        id: Int, title: String, projectID: String = "", projectName: String, repositoryName: String,
        author: Identity, creationDate: Date, isDraft: Bool = false, reviewers: [Reviewer] = [],
        hasMergeConflict: Bool = false
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.projectName = projectName
        self.repositoryName = repositoryName
        self.author = author
        self.creationDate = creationDate
        self.isDraft = isDraft
        self.reviewers = reviewers
        self.hasMergeConflict = hasMergeConflict
    }

    /// Prête à merger : publiée, sans conflit, toutes les policies bloquantes approuvées.
    public func isReady(_ checks: PRChecks?) -> Bool {
        !isDraft && !hasMergeConflict && checks?.blockingSatisfied == true
    }
}

public enum PipelineStatus: String, Codable, Hashable, Sendable {
    case queued, running, expired, passed, failed

    public var isPending: Bool { self == .queued || self == .running || self == .expired }

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .expired: "Expired — re-queue needed"
        case .passed: "Succeeded"
        case .failed: "Failed"
        }
    }
}

/// Évaluation d'une policy *Build validation* sur une PR.
public struct PipelineCheck: Codable, Hashable, Sendable, Identifiable {
    /// Id de la configuration de policy : stable d'un build à l'autre.
    public var id: Int
    public var name: String
    public var status: PipelineStatus
    public var isRequired: Bool
    public var buildID: Int?

    public init(id: Int, name: String, status: PipelineStatus, isRequired: Bool = true, buildID: Int? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.isRequired = isRequired
        self.buildID = buildID
    }
}

public struct PRChecks: Codable, Hashable, Sendable {
    /// Ordre renvoyé par ADO.
    public var pipelines: [PipelineCheck]
    /// Toutes les policies bloquantes approuvées (builds, reviewers, WI liés, commentaires…).
    public var blockingSatisfied: Bool

    public init(pipelines: [PipelineCheck], blockingSatisfied: Bool) {
        self.pipelines = pipelines
        self.blockingSatisfied = blockingSatisfied
    }
}

public struct Comment: Codable, Hashable, Sendable {
    public var id: Int
    public var author: Identity
    public var text: String
    public var isSystem: Bool

    public init(id: Int, author: Identity, text: String, isSystem: Bool = false) {
        self.id = id
        self.author = author
        self.text = text
        self.isSystem = isSystem
    }
}

public struct PRThread: Codable, Hashable, Sendable {
    public var id: Int
    public var comments: [Comment]

    public init(id: Int, comments: [Comment]) {
        self.id = id
        self.comments = comments
    }
}

public enum StateCategory: String, Codable, Hashable, Sendable {
    case proposed = "Proposed"
    case inProgress = "InProgress"
    case resolved = "Resolved"
    case completed = "Completed"
    case removed = "Removed"

    public var isClosed: Bool { self == .completed || self == .removed }

    public var label: String {
        switch self {
        case .proposed: "Proposed"
        case .inProgress: "In Progress"
        case .resolved: "Resolved"
        case .completed: "Completed"
        case .removed: "Removed"
        }
    }
}

public struct StateDef: Codable, Hashable, Sendable {
    public var name: String
    public var category: StateCategory

    public init(name: String, category: StateCategory) {
        self.name = name
        self.category = category
    }
}

public struct WorkItemType: Codable, Hashable, Sendable {
    public var name: String
    /// Couleur hex ADO sans `#` (ex. `CC293D`).
    public var color: String?
    public var states: [StateDef]

    public init(name: String, color: String? = nil, states: [StateDef]) {
        self.name = name
        self.color = color
        self.states = states
    }
}

public struct WorkItem: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var typeName: String
    public var state: String
    public var projectName: String
    public var commentCount: Int

    public init(id: Int, title: String, typeName: String, state: String, projectName: String, commentCount: Int = 0) {
        self.id = id
        self.title = title
        self.typeName = typeName
        self.state = state
        self.projectName = projectName
        self.commentCount = commentCount
    }
}

/// Types de WI par projet puis par nom de type.
public typealias TypeCatalog = [String: [String: WorkItemType]]

public struct Snapshot: Codable, Hashable, Sendable {
    public var me: Identity
    public var toReview: [PullRequest]
    public var myPRs: [PullRequest]
    /// Threads de mes PRs, par id de PR.
    public var threads: [Int: [PRThread]]
    public var workItems: [WorkItem]
    /// Policies des PRs (To Review et My PRs), par id de PR. Absente : inconnue (erreur API).
    public var checks: [Int: PRChecks]
    /// Derniers commentaires (récents d'abord) des WI dont le compteur a augmenté.
    public var workItemComments: [Int: [Comment]]
    public var types: TypeCatalog
    public var inaccessibleProjects: [String]
    public var fetchedAt: Date

    public init(
        me: Identity, toReview: [PullRequest] = [], myPRs: [PullRequest] = [], threads: [Int: [PRThread]] = [:],
        checks: [Int: PRChecks] = [:], workItems: [WorkItem] = [], workItemComments: [Int: [Comment]] = [:],
        types: TypeCatalog = [:],
        inaccessibleProjects: [String] = [], fetchedAt: Date
    ) {
        self.me = me
        self.toReview = toReview
        self.myPRs = myPRs
        self.threads = threads
        self.checks = checks
        self.workItems = workItems
        self.workItemComments = workItemComments
        self.types = types
        self.inaccessibleProjects = inaccessibleProjects
        self.fetchedAt = fetchedAt
    }
}
