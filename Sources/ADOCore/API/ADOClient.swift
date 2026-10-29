import Foundation

/// Client REST Azure DevOps (api-version 7.1), auth Basic avec PAT.
public struct ADOClient: Sendable {
    public static let batchSize = 200
    static let workItemFields = [
        "System.Id", "System.Title", "System.WorkItemType", "System.State", "System.TeamProject",
        "System.CommentCount",
    ]

    public let org: OrgURL
    private let pat: String
    private let transport: HTTPTransport

    public init(org: OrgURL, pat: String, transport: HTTPTransport = URLSessionTransport()) {
        self.org = org
        self.pat = pat
        self.transport = transport
    }

    // MARK: - Endpoints

    public func connectionData() async throws -> Identity {
        let dto: ConnectionDataDTO = try await get(org.base.appending(path: "_apis/connectionData"), version: nil)
        return Identity(id: dto.authenticatedUser.id, displayName: dto.authenticatedUser.providerDisplayName)
    }

    public func projects() async throws -> [Project] {
        let dto: ListDTO<ProjectDTO> = try await get(
            org.base.appending(path: "_apis/projects"), query: [URLQueryItem(name: "$top", value: "500")])
        return dto.value.map { Project(id: $0.id, name: $0.name) }
    }

    public enum PRRole: Sendable { case reviewer, creator }

    public func activePullRequests(project: String, userID: String, role: PRRole) async throws -> [PullRequest] {
        let criterion = role == .reviewer ? "searchCriteria.reviewerId" : "searchCriteria.creatorId"
        let dto: ListDTO<PullRequestDTO> = try await get(
            org.base.appending(path: project).appending(path: "_apis/git/pullrequests"),
            query: [
                URLQueryItem(name: "searchCriteria.status", value: "active"),
                URLQueryItem(name: criterion, value: userID),
                URLQueryItem(name: "$top", value: "500"),
            ])
        return dto.value.map(\.model)
    }

    public func threads(project: String, repository: String, pullRequestID: Int) async throws -> [PRThread] {
        let dto: ListDTO<ThreadDTO> = try await get(
            org.base.appending(path: project).appending(path: "_apis/git/repositories").appending(path: repository)
                .appending(path: "pullRequests").appending(path: String(pullRequestID)).appending(path: "threads"))
        return dto.value.filter { $0.isDeleted != true }.map(\.model)
    }

    /// Évaluations de policies d'une PR (builds, reviewers, WI liés…).
    public func prChecks(projectID: String, projectName: String, pullRequestID: Int) async throws -> PRChecks {
        let dto: ListDTO<PolicyEvaluationDTO> = try await get(
            org.base.appending(path: projectName).appending(path: "_apis/policy/evaluations"),
            query: [
                URLQueryItem(
                    name: "artifactId", value: "vstfs:///CodeReview/CodeReviewId/\(projectID)/\(pullRequestID)")
            ],
            version: "7.1-preview.1")
        return dto.value.model
    }

    public func workItemTypes(project: String) async throws -> [WorkItemType] {
        let dto: ListDTO<WorkItemTypeDTO> = try await get(
            org.base.appending(path: project).appending(path: "_apis/wit/workitemtypes"))
        return dto.value.map(\.model)
    }

    /// Ids des WI assignés à l'utilisateur dans `projects`, hors `excludedStates`.
    public func assignedWorkItemIDs(projects: [String], excludedStates: Set<String>) async throws -> [Int] {
        guard !projects.isEmpty else { return [] }
        var wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me"
        wiql += " AND [System.TeamProject] IN (\(projects.map(Self.quote).joined(separator: ", ")))"
        if !excludedStates.isEmpty {
            wiql += " AND [System.State] NOT IN (\(excludedStates.sorted().map(Self.quote).joined(separator: ", ")))"
        }
        wiql += " ORDER BY [System.ChangedDate] DESC"
        let dto: WiqlResultDTO = try await send(
            "POST", org.base.appending(path: "_apis/wit/wiql"), query: [URLQueryItem(name: "$top", value: "1000")],
            body: ["query": wiql])
        return dto.workItems.map(\.id)
    }

    public func workItems(ids: [Int]) async throws -> [WorkItem] {
        var result: [WorkItem] = []
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let chunk = Array(ids[start..<min(start + Self.batchSize, ids.count)])
            // errorPolicy omit : un WI supprimé entre la WIQL et le batch revient `null` au lieu d'un échec.
            let dto: ListDTO<WorkItemDTO?> = try await send(
                "POST", org.base.appending(path: "_apis/wit/workitemsbatch"),
                body: WorkItemsBatchBody(ids: chunk, fields: Self.workItemFields, errorPolicy: "omit"))
            result += dto.value.compactMap { $0?.model }
        }
        return result
    }

    /// Commentaires les plus récents d'abord.
    public func workItemComments(project: String, id: Int, top: Int = 5) async throws -> [Comment] {
        let dto: CommentListDTO = try await get(
            org.base.appending(path: project).appending(path: "_apis/wit/workItems").appending(path: String(id))
                .appending(path: "comments"),
            query: [URLQueryItem(name: "$top", value: String(top)), URLQueryItem(name: "order", value: "desc")],
            version: "7.1-preview.4")
        return dto.comments.map(\.model)
    }

    public func updateState(workItemID: Int, to state: String) async throws -> WorkItem {
        let patch = [PatchOperation(op: "add", path: "/fields/System.State", value: state)]
        let dto: WorkItemDTO = try await send(
            "PATCH", org.base.appending(path: "_apis/wit/workitems").appending(path: String(workItemID)), body: patch,
            contentType: "application/json-patch+json")
        return dto.model
    }

    // MARK: - Transport

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func get<T: Decodable>(_ url: URL, query: [URLQueryItem] = [], version: String? = "7.1") async throws -> T {
        try await send("GET", url, query: query, body: String?.none, version: version)
    }

    private func send<T: Decodable, B: Encodable>(
        _ method: String, _ url: URL, query: [URLQueryItem] = [], body: B?, version: String? = "7.1",
        contentType: String = "application/json"
    ) async throws -> T {
        var items = query
        if let version { items.append(URLQueryItem(name: "api-version", value: version)) }
        var request = URLRequest(url: items.isEmpty ? url : url.appending(queryItems: items))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic " + Data(":\(pat)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            // Synchro remplacée ou arrêtée : pas une erreur réseau.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw ADOError.wrap(error)
        }

        switch response.statusCode {
        // 203 : ADO renvoie la page de login HTML quand le PAT est refusé.
        case 203, 401: throw ADOError.unauthorized
        case 404: throw ADOError.notFound
        case 429: throw ADOError.rateLimited
        case 200..<300: break
        default:
            let message = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.message
            throw ADOError.server(status: response.statusCode, message: message ?? "HTTP \(response.statusCode)")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ADOError.decoding(String(describing: error))
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(
                text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
            {
                return date
            }
            return try Date(text, strategy: .iso8601)
        }
        return decoder
    }()
}
