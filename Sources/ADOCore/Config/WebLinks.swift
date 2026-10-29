import Foundation

/// URLs web ADO ouvertes dans le navigateur.
public struct WebLinks: Sendable {
    public let org: OrgURL

    public init(org: OrgURL) {
        self.org = org
    }

    public func pullRequest(_ pr: PullRequest) -> URL {
        org.base.appending(path: pr.projectName).appending(path: "_git").appending(path: pr.repositoryName)
            .appending(path: "pullrequest").appending(path: String(pr.id))
    }

    public func workItem(id: Int, project: String) -> URL {
        org.base.appending(path: project).appending(path: "_workitems").appending(path: "edit")
            .appending(path: String(id))
    }

    public func workItem(_ wi: WorkItem) -> URL {
        workItem(id: wi.id, project: wi.projectName)
    }

    /// Liste « Mes pull requests » de l'organisation.
    public var allPullRequests: URL { org.base.appending(path: "_pulls") }

    public func assignedWorkItems(project: String) -> URL {
        org.base.appending(path: project).appending(path: "_workitems").appending(path: "assignedtome")
    }
}
