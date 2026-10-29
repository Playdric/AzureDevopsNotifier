import Foundation
import Synchronization

@testable import ADOCore

/// Transport HTTP simulé : route chaque requête vers une réponse, garde l'historique.
final class StubTransport: HTTPTransport {
    typealias Route = @Sendable (URLRequest) -> (Int, Data)?
    private let route: Route
    private let log = Mutex<[URLRequest]>([])

    init(_ route: @escaping Route) {
        self.route = route
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        guard let (status, data) = route(request) else { throw URLError(.notConnectedToInternet) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

func query(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

let org = OrgURL("https://dev.azure.com/contoso")!
let me = Identity(id: "u-me", displayName: "Cédric Nanteau")
let sarah = Identity(id: "u-sarah", displayName: "Sarah Chen")
let priya = Identity(id: "u-priya", displayName: "Priya Natarajan")
let t0 = Date(timeIntervalSince1970: 1_800_000_000)

let agileBug = WorkItemType(
    name: "Bug", color: "CC293D",
    states: [
        StateDef(name: "New", category: .proposed), StateDef(name: "Active", category: .inProgress),
        StateDef(name: "Resolved", category: .resolved), StateDef(name: "Closed", category: .completed),
        StateDef(name: "Blocked", category: .inProgress),
    ])
let agileStory = WorkItemType(
    name: "User Story", color: "009CCC",
    states: [
        StateDef(name: "New", category: .proposed), StateDef(name: "Active", category: .inProgress),
        StateDef(name: "Blocked", category: .inProgress), StateDef(name: "Closed", category: .completed),
        StateDef(name: "Removed", category: .removed),
    ])
let scrumPBI = WorkItemType(
    name: "Product Backlog Item", color: "009CCC",
    states: [
        StateDef(name: "New", category: .proposed), StateDef(name: "Approved", category: .proposed),
        StateDef(name: "Committed", category: .inProgress), StateDef(name: "Done", category: .completed),
        StateDef(name: "Removed", category: .removed),
    ])
let types: TypeCatalog = [
    "Billing": ["Bug": agileBug, "User Story": agileStory],
    "Mobile": ["Product Backlog Item": scrumPBI],
]

func pr(
    _ id: Int, title: String = "PR", author: Identity = sarah, reviewers: [Reviewer] = [], draft: Bool = false,
    conflict: Bool = false
) -> PullRequest {
    PullRequest(
        id: id, title: title, projectID: "p1", projectName: "Billing", repositoryName: "payments-api", author: author,
        creationDate: t0, isDraft: draft, reviewers: reviewers, hasMergeConflict: conflict)
}

func checks(_ pipelines: PipelineCheck..., ready: Bool = false) -> PRChecks {
    PRChecks(pipelines: pipelines, blockingSatisfied: ready)
}

func wi(_ id: Int, type: String = "Bug", state: String = "Active", project: String = "Billing", comments: Int = 0)
    -> WorkItem
{
    WorkItem(id: id, title: "WI \(id)", typeName: type, state: state, projectName: project, commentCount: comments)
}

func snap(
    toReview: [PullRequest] = [], myPRs: [PullRequest] = [], threads: [Int: [PRThread]] = [:],
    checks: [Int: PRChecks] = [:], workItems: [WorkItem] = [], wiComments: [Int: [Comment]] = [:], at date: Date = t0
) -> Snapshot {
    Snapshot(
        me: me, toReview: toReview, myPRs: myPRs, threads: threads, checks: checks, workItems: workItems,
        workItemComments: wiComments,
        types: types, fetchedAt: date)
}
