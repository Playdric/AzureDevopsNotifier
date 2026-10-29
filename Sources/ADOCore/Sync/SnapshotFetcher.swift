import Foundation

/// Assemble un `Snapshot` pour les projets suivis.
public struct SnapshotFetcher: Sendable {
    public let client: ADOClient
    public let me: Identity
    public let projects: [String]

    public init(client: ADOClient, me: Identity, projects: [String]) {
        self.client = client
        self.me = me
        self.projects = projects
    }

    public func fetch(previous: Snapshot?, refreshTypes: Bool, now: Date = .now) async throws -> Snapshot {
        var inaccessible = Set<String>()

        var types = previous?.types ?? [:]
        if refreshTypes || previous == nil {
            types = [:]
            for project in projects {
                do {
                    let list = try await client.workItemTypes(project: project)
                    types[project] = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                } catch ADOError.notFound {
                    inaccessible.insert(project)
                }
            }
        }

        var toReview: [PullRequest] = []
        var myPRs: [PullRequest] = []
        for project in projects where !inaccessible.contains(project) {
            do {
                toReview += try await client.activePullRequests(project: project, userID: me.id, role: .reviewer)
                myPRs += try await client.activePullRequests(project: project, userID: me.id, role: .creator)
            } catch ADOError.notFound {
                inaccessible.insert(project)
            }
        }
        // Reviewer direct uniquement (AC5) ; une PR que j'ai créée reste dans My PRs.
        toReview = toReview.filter { pr in
            pr.author.id != me.id && pr.reviewers.contains { $0.identity.id == me.id && !$0.isContainer }
        }

        var threads: [Int: [PRThread]] = [:]
        for pr in myPRs {
            threads[pr.id] = try await client.threads(
                project: pr.projectName, repository: pr.repositoryName, pullRequestID: pr.id)
        }

        let accessible = projects.filter { !inaccessible.contains($0) }
        let ids = try await client.assignedWorkItemIDs(
            projects: accessible, excludedStates: StateMenu.closedEverywhere(types))
        let workItems = try await client.workItems(ids: ids).filter { StateMenu.isOpen($0, types: types) }

        let oldCounts = Dictionary(
            (previous?.workItems ?? []).map { ($0.id, $0.commentCount) }, uniquingKeysWith: { a, _ in a })
        var comments: [Int: [Comment]] = [:]
        for wi in workItems {
            guard let old = oldCounts[wi.id], wi.commentCount > old else { continue }
            comments[wi.id] = try await client.workItemComments(project: wi.projectName, id: wi.id)
        }

        return Snapshot(
            me: me, toReview: toReview, myPRs: myPRs, threads: threads, workItems: workItems,
            workItemComments: comments, types: types, inaccessibleProjects: inaccessible.sorted(), fetchedAt: now)
    }
}
