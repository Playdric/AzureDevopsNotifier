import Foundation
import Testing

@testable import ADOCore

struct ADOClientTests {
    private func client(_ route: @escaping StubTransport.Route) -> (ADOClient, StubTransport) {
        let transport = StubTransport(route)
        return (ADOClient(org: org, pat: "secret-pat", transport: transport), transport)
    }

    @Test func connectionDataSendsBasicAuth() async throws {
        let (client, transport) = client { _ in (200, fixture("connectionData")) }
        let identity = try await client.connectionData()
        #expect(identity == me)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/contoso/_apis/connectionData")
        #expect(
            request.value(forHTTPHeaderField: "Authorization") == "Basic "
                + Data(":secret-pat".utf8).base64EncodedString())
    }

    // AC2
    @Test(arguments: [401, 203])
    func rejectedTokenIsUnauthorized(status: Int) async {
        let (client, _) = client { _ in (status, Data("<html>Sign in</html>".utf8)) }
        await #expect(throws: ADOError.unauthorized) { try await client.connectionData() }
    }

    @Test func offlineIsNetworkError() async {
        let (client, _) = client { _ in nil }
        await #expect {
            try await client.projects()
        } throws: { error in
            if case .network = error as? ADOError { true } else { false }
        }
    }

    // Review #1
    @Test func cancelledRequestIsCancellationNotNetwork() async {
        struct Cancelled: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.cancelled) }
        }
        let client = ADOClient(org: org, pat: "x", transport: Cancelled())
        await #expect(throws: CancellationError.self) { try await client.projects() }
    }

    // Review #2 : WI disparu entre la WIQL et le batch → ignoré.
    @Test func batchOmitsMissingWorkItems() async throws {
        let body =
            #"{"count":2,"value":[null,{"id":7,"fields":{"System.Title":"T","System.WorkItemType":"Bug","System.State":"New","System.TeamProject":"Billing"}}]}"#
        let (client, transport) = client { _ in (200, Data(body.utf8)) }
        let items = try await client.workItems(ids: [6, 7])
        #expect(items.map(\.id) == [7])
        let sent = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        #expect(sent["errorPolicy"] as? String == "omit")
    }

    @Test func statusMapping() async {
        let (notFound, _) = client { _ in (404, Data()) }
        await #expect(throws: ADOError.notFound) { try await notFound.projects() }
        let (throttled, _) = client { _ in (429, Data()) }
        await #expect(throws: ADOError.rateLimited) { try await throttled.projects() }
        let (garbage, _) = client { _ in (200, Data("{}".utf8)) }
        await #expect { try await garbage.projects() } throws: { error in
            if case .decoding = error as? ADOError { true } else { false }
        }
    }

    @Test func projects() async throws {
        let (client, _) = client { _ in (200, fixture("projects")) }
        #expect(try await client.projects().map(\.name) == ["Billing", "Mobile"])
    }

    @Test func pullRequestsQueryAndDecoding() async throws {
        let (client, transport) = client { _ in (200, fixture("pullrequests-reviewer")) }
        let prs = try await client.activePullRequests(project: "Billing", userID: "u-me", role: .reviewer)
        #expect(prs.count == 3)
        #expect(prs[0].reviewers.map(\.vote) == [.none, .approved])
        #expect(prs[0].creationDate.timeIntervalSince1970 > 0)
        #expect(prs[1].reviewers[0].isContainer)
        #expect(prs[2].isDraft)
        let request = transport.requests[0]
        #expect(query(request, "searchCriteria.reviewerId") == "u-me")
        #expect(query(request, "searchCriteria.status") == "active")
        #expect(query(request, "api-version") == "7.1")
    }

    @Test func threadsDropDeletedAndFlagSystem() async throws {
        let (client, _) = client { _ in (200, fixture("threads")) }
        let threads = try await client.threads(project: "Billing", repository: "r", pullRequestID: 1)
        #expect(threads.map(\.id) == [1, 2])
        #expect(threads[0].comments.map(\.id) == [1, 2])
        #expect(threads[1].comments[0].isSystem)
    }

    @Test func workItemQueryEscapesAndExcludes() async throws {
        let (client, transport) = client { _ in (200, fixture("wiql")) }
        let ids = try await client.assignedWorkItemIDs(
            projects: ["Billing", "O'Neil"], excludedStates: ["Removed", "Closed"])
        #expect(ids == [48213, 1207, 999])
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: String]
        let wiql = try #require(body["query"])
        #expect(wiql.contains("[System.AssignedTo] = @Me"))
        #expect(wiql.contains("IN ('Billing', 'O''Neil')"))
        #expect(wiql.contains("NOT IN ('Closed', 'Removed')"))
    }

    @Test func workItemsAreBatchedBy200() async throws {
        let (client, transport) = client { _ in (200, fixture("workitemsbatch")) }
        let items = try await client.workItems(ids: Array(1...450))
        #expect(transport.requests.count == 3)
        #expect(items.count == 9)
        #expect(items[0].commentCount == 2)
        #expect(items[1].commentCount == 0)
    }

    @Test func workItemTypes() async throws {
        let (client, _) = client { _ in (200, fixture("workitemtypes-scrum")) }
        let list = try await client.workItemTypes(project: "Mobile")
        #expect(list[0].states.map(\.category) == [.proposed, .proposed, .inProgress, .completed, .removed])
        #expect(list[0].color == "009CCC")
    }

    @Test func commentsArePlainText() async throws {
        let (client, transport) = client { _ in (200, fixture("comments")) }
        let comments = try await client.workItemComments(project: "Billing", id: 48213)
        #expect(comments[0].text == "Repro on contoso.fr tenant")
        #expect(comments[0].author == priya)
        #expect(query(transport.requests[0], "api-version") == "7.1-preview.4")
    }

    // AC7b
    @Test func updateStateSendsJSONPatch() async throws {
        let (client, transport) = client { _ in (200, fixture("patch-ok")) }
        let updated = try await client.updateState(workItemID: 48213, to: "Resolved")
        #expect(updated.state == "Resolved")
        let request = transport.requests[0]
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json-patch+json")
        let ops = try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: String]]
        #expect(ops == [["op": "add", "path": "/fields/System.State", "value": "Resolved"]])
    }

    // AC8
    @Test func transitionRefusalCarriesADOMessage() async {
        let (client, _) = client { _ in (400, fixture("error-transition")) }
        await #expect(
            throws: ADOError.server(
                status: 400,
                message: "TF401320: Rule Error for field Resolved Reason. Error code: Required, InvalidEmpty.")
        ) { try await client.updateState(workItemID: 48213, to: "Closed") }
    }
}

struct SnapshotFetcherTests {
    private static func route(_ request: URLRequest) -> (Int, Data)? {
        let path = request.url!.path()
        if path.hasSuffix("/Billing/_apis/wit/workitemtypes") { return (200, fixture("workitemtypes-agile")) }
        if path.hasSuffix("/Mobile/_apis/wit/workitemtypes") { return (200, fixture("workitemtypes-scrum")) }
        if path.contains("/Gone/") { return (404, Data()) }
        if path.hasSuffix("/Billing/_apis/git/pullrequests") {
            return query(request, "searchCriteria.reviewerId") != nil
                ? (200, fixture("pullrequests-reviewer")) : (200, fixture("pullrequests-creator"))
        }
        if path.hasSuffix("/_apis/git/pullrequests") { return (200, Data(#"{"value":[]}"#.utf8)) }
        if path.hasSuffix("/threads") { return (200, fixture("threads")) }
        if path.hasSuffix("/_apis/wit/wiql") { return (200, fixture("wiql")) }
        if path.hasSuffix("/_apis/wit/workitemsbatch") { return (200, fixture("workitemsbatch")) }
        if path.hasSuffix("/comments") { return (200, fixture("comments")) }
        return nil
    }

    private func fetcher(projects: [String] = ["Billing", "Mobile"]) -> (SnapshotFetcher, StubTransport) {
        let transport = StubTransport(Self.route)
        return (
            SnapshotFetcher(client: ADOClient(org: org, pat: "x", transport: transport), me: me, projects: projects),
            transport
        )
    }

    // AC4, AC5, AC24
    @Test func buildsFilteredSnapshot() async throws {
        let (fetcher, transport) = fetcher()
        let snapshot = try await fetcher.fetch(previous: nil, refreshTypes: true, now: t0)
        #expect(snapshot.toReview.map(\.id) == [101])  // 102 groupe seul, 103 créée par moi
        #expect(snapshot.myPRs.map(\.id) == [103])
        #expect(snapshot.threads[103]?.count == 2)
        #expect(snapshot.workItems.map(\.id) == [48213, 1207])  // 999 Done exclu
        #expect(snapshot.types["Mobile"]?["Product Backlog Item"] != nil)
        #expect(snapshot.workItemComments.isEmpty)  // pas de précédent → pas de commentaires chargés
        #expect(snapshot.fetchedAt == t0)

        let wiql =
            try JSONSerialization.jsonObject(
                with: transport.requests.first { $0.url!.path().hasSuffix("wiql") }!.httpBody!) as! [String: String]
        #expect(wiql["query"]!.contains("IN ('Billing', 'Mobile')"))
        #expect(wiql["query"]!.contains("NOT IN ('Closed', 'Done', 'Removed')"))
    }

    @Test func reusesTypesAndLoadsCommentsOnlyWhenCountGrows() async throws {
        let (fetcher, transport) = fetcher()
        var previous = try await fetcher.fetch(previous: nil, refreshTypes: true, now: t0)
        previous.workItems = previous.workItems.map {
            var w = $0; w.commentCount = 1; return w
        }
        let before = transport.requests.count

        let next = try await fetcher.fetch(previous: previous, refreshTypes: false, now: t0)
        let calls = transport.requests[before...].map { $0.url!.path() }
        #expect(!calls.contains { $0.hasSuffix("workitemtypes") })
        #expect(calls.filter { $0.hasSuffix("/comments") } == ["/contoso/Billing/_apis/wit/workItems/48213/comments"])
        #expect(next.workItemComments[48213]?.count == 2)
    }

    @Test func inaccessibleProjectIsSkipped() async throws {
        let (fetcher, _) = fetcher(projects: ["Billing", "Gone"])
        let snapshot = try await fetcher.fetch(previous: nil, refreshTypes: true, now: t0)
        #expect(snapshot.inaccessibleProjects == ["Gone"])
        #expect(snapshot.toReview.map(\.id) == [101])
    }
}
