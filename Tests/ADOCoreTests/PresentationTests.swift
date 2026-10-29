import Foundation
import Testing

@testable import ADOCore

struct PanelStateTests {
    private var prefs: Preferences {
        var p = Preferences()
        p.orgURL = org
        p.me = me
        p.projects = [Project(id: "p1", name: "Billing")]
        return p
    }

    // AC1
    @Test func notConfigured() {
        let state = PanelState.make(prefs: Preferences(), snapshot: nil, status: .idle, seen: [], now: t0)
        #expect(!state.isConfigured)
        #expect(state.icon == .notConfigured)
    }

    @Test func firstSyncShowsLoading() {
        let state = PanelState.make(prefs: prefs, snapshot: nil, status: .syncing, seen: [], now: t0)
        #expect(state.isLoading)
        #expect(state.icon == .normal)
    }

    // AC20
    @Test func activityCountsReviewsAndUnseenWorkItems() {
        let s = snap(toReview: [pr(1)], workItems: [wi(1), wi(2)])
        let state = PanelState.make(
            prefs: prefs, snapshot: s, status: .idle, seen: [PanelState.seenKey(wi: 1)], now: t0)
        #expect(state.icon == .activity(2))
        #expect(state.workItems.rows.map(\.isNew) == [false, true])
        let calm = PanelState.make(
            prefs: prefs, snapshot: snap(workItems: [wi(1)]), status: .idle, seen: ["wi:1"], now: t0)
        #expect(calm.icon == .normal)
    }

    // AC17, PAT expiré
    @Test func errorBannersKeepData() {
        let s = snap(toReview: [pr(1)])
        let offline = PanelState.make(prefs: prefs, snapshot: s, status: .failed(.network("x")), seen: [], now: t0)
        #expect(offline.banners == [.networkError(lastSync: t0)])
        #expect(offline.icon == .error)
        #expect(offline.toReview.rows.count == 1)
        let throttled = PanelState.make(prefs: prefs, snapshot: s, status: .failed(.rateLimited), seen: [], now: t0)
        #expect(throttled.banners == [.throttled(lastSync: t0)])
        let auth = PanelState.make(prefs: prefs, snapshot: nil, status: .failed(.unauthorized), seen: [], now: t0)
        #expect(auth.banners == [.tokenExpired(lastSync: nil)])
        #expect(!auth.isLoading)
    }

    // AC28
    @Test func mutedIconAndBanner() {
        var p = prefs
        p.mute = .until(t0.addingTimeInterval(60))
        let state = PanelState.make(
            prefs: p, snapshot: snap(toReview: [pr(1)]), status: .failed(.rateLimited), seen: [], now: t0)
        #expect(state.icon == .muted)
        #expect(state.banners.last == .muted(until: t0.addingTimeInterval(60)))
        let expired = PanelState.make(
            prefs: p, snapshot: snap(), status: .idle, seen: [], now: t0.addingTimeInterval(61))
        #expect(expired.banners.isEmpty)
    }

    // AC22, AC36, AC7
    @Test func workItemRowKeepsCurrentStateAndOriginalTitle() {
        var p = prefs
        p.hiddenStates = ["Active", "Blocked"]
        p.tags = TagSettings(hideAll: true)
        var item = wi(1, state: "Active")
        item.title = "[Prod][P1] Login fails"
        let row = PanelState.make(prefs: p, snapshot: snap(workItems: [item]), status: .idle, seen: [], now: t0)
            .workItems.rows[0]
        #expect(row.state == "Active")
        #expect(row.category == .inProgress)
        #expect(row.stateOptions.map(\.name) == ["New", "Resolved", "Closed"])
        #expect(row.title == "Login fails")
        #expect(row.originalTitle == "[Prod][P1] Login fails")
        #expect(row.typeColor == "CC293D")
    }

    @Test func myPRVotesExcludeMe() {
        let mine = pr(
            3, author: me,
            reviewers: [
                Reviewer(identity: priya, vote: .approved), Reviewer(identity: sarah, vote: .approved),
                Reviewer(identity: me, vote: .approved),
                Reviewer(identity: Identity(id: "z", displayName: "Z"), vote: .rejected),
            ])
        let row = PanelState.make(prefs: prefs, snapshot: snap(myPRs: [mine]), status: .idle, seen: [], now: t0).myPRs
            .rows[0]
        #expect(row.votes == [VoteCount(vote: .approved, count: 2), VoteCount(vote: .rejected, count: 1)])
    }

    @Test func sectionsAreCappedWithOverflowLink() {
        let many = (1...60).map { wi($0) }
        let state = PanelState.make(prefs: prefs, snapshot: snap(workItems: many), status: .idle, seen: [], now: t0)
        #expect(state.workItems.rows.count == 50)
        #expect(state.workItems.total == 60)
        #expect(
            state.workItems.overflowURL?.absoluteString
                == "https://dev.azure.com/contoso/Billing/_workitems/assignedtome")
        #expect(state.toReview.overflowURL == nil)
    }

    // AC42, AC44
    @Test func listHiddenStatesFilterRowsAndBadge() {
        var p = prefs
        p.listHiddenStates = ["Resolved"]
        let s = snap(workItems: [wi(1, state: "Active"), wi(2, state: "Resolved")])
        let state = PanelState.make(prefs: p, snapshot: s, status: .idle, seen: [], now: t0)
        #expect(state.workItems.rows.map(\.id) == [1])
        #expect(state.workItems.total == 1)
        #expect(state.workItems.hiddenCount == 1)
        #expect(state.icon == .activity(1))

        let back = snap(workItems: [wi(1, state: "Active"), wi(2, state: "Active")])
        let after = PanelState.make(prefs: p, snapshot: back, status: .idle, seen: [], now: t0)
        #expect(after.workItems.rows.map(\.id) == [1, 2])
        #expect(after.workItems.hiddenCount == 0)
    }

    // AC43, AC45 : filtres d'affichage sans effet sur les événements.
    @Test func displayFiltersDoNotAffectEvents() {
        var p = prefs
        p.listHiddenStates = ["Resolved"]
        p.hideDraftsToReview = true
        var draft = pr(8)
        draft.isDraft = true
        let old = snap(workItems: [wi(2, state: "Resolved", comments: 0)])
        let new = snap(
            toReview: [draft], workItems: [wi(2, state: "Resolved", comments: 1), wi(3, state: "Resolved")],
            wiComments: [2: [Comment(id: 1, author: priya, text: "hi")]])
        let state = PanelState.make(prefs: p, snapshot: new, status: .idle, seen: [], now: t0)
        #expect(state.workItems.rows.isEmpty)
        #expect(state.toReview.rows.isEmpty)
        #expect(EventDiffer.diff(old: old, new: new).count == 3)
    }

    // AC45, AC46
    @Test func draftFiltersPerSection() {
        var draftReview = pr(1)
        draftReview.isDraft = true
        var draftMine = pr(2, author: me)
        draftMine.isDraft = true
        let s = snap(toReview: [draftReview, pr(3)], myPRs: [draftMine, pr(4, author: me)])

        var p = prefs
        p.hideDraftsToReview = true
        let reviewOnly = PanelState.make(prefs: p, snapshot: s, status: .idle, seen: [], now: t0)
        #expect(reviewOnly.toReview.rows.map(\.id) == [3])
        #expect(reviewOnly.toReview.hiddenCount == 1)
        #expect(reviewOnly.myPRs.rows.map(\.id) == [2, 4])
        #expect(reviewOnly.icon == .activity(1))

        p.hideDraftsToReview = false
        p.hideDraftsMine = true
        let mineOnly = PanelState.make(prefs: p, snapshot: s, status: .idle, seen: [], now: t0)
        #expect(mineOnly.toReview.rows.map(\.id) == [1, 3])
        #expect(mineOnly.myPRs.rows.map(\.id) == [4])
    }
}

struct PRRowCITests {
    private var prefs: Preferences {
        var p = Preferences()
        p.orgURL = org
        p.me = me
        p.projects = [Project(id: "p1", name: "Billing")]
        return p
    }
    private func build(_ id: Int, _ name: String, _ status: PipelineStatus, required: Bool = true) -> PipelineCheck {
        PipelineCheck(id: id, name: name, status: status, isRequired: required)
    }
    private func row(_ c: PRChecks?, pr p: PullRequest = pr(1, author: me), mine: Bool = true) -> PRRow {
        let s =
            mine
            ? snap(myPRs: [p], checks: c.map { [p.id: $0] } ?? [:])
            : snap(toReview: [p], checks: c.map { [p.id: $0] } ?? [:])
        let state = PanelState.make(prefs: prefs, snapshot: s, status: .idle, seen: [], now: t0)
        return (mine ? state.myPRs : state.toReview).rows[0]
    }

    // AC1, AC5
    @Test func failuresCountedAndDetailed() {
        let r = row(
            checks(
                build(1, "PR-Build", .failed), build(2, "Unit Tests", .failed),
                build(3, "Lint", .passed, required: false)))
        #expect(r.pipelines.map(\.id) == [1, 2, 3])
        #expect(r.ciAccessibilityLabel == "CI: 2 of 3 failed")
        #expect(r.ciHeader == "CI · 2 of 3 failed")
    }

    // AC2, cas limite expiré
    @Test func pendingAndPassed() {
        let pending = row(checks(build(1, "A", .running), build(2, "B", .queued), build(3, "C", .expired)))
        #expect(pending.ciAccessibilityLabel == "CI: running")
        #expect(pending.ciHeader == "CI · 3 of 3 pending")
        #expect(pending.pipelines.map(\.status.label) == ["Running", "Queued", "Expired — re-queue needed"])
        let passed = row(checks(build(1, "A", .passed), build(2, "B", .passed)))
        #expect(passed.ciAccessibilityLabel == "CI: succeeded")
        #expect(passed.ciHeader == "CI · all 2 succeeded")
    }

    // AC3, AC16
    @Test func nothingWithoutPipelines() {
        for r in [row(nil), row(checks())] {
            #expect(r.pipelines.isEmpty)
            #expect(r.ciHeader == nil)
            #expect(r.ciAccessibilityLabel == nil)
        }
    }

    // AC4 ; optionnel KO + build requis en cours : encore en attente.
    @Test func optionalFailureIsDistinct() {
        let r = row(checks(build(1, "A", .passed), build(2, "Perf", .failed, required: false)))
        #expect(r.ciAccessibilityLabel == "CI: optional pipeline failed")
        #expect(r.ciHeader == "CI · optional pipeline failed")
        #expect(!r.pipelines[1].isRequired)
        let stillRunning = row(checks(build(1, "A", .running), build(2, "Perf", .failed, required: false)))
        #expect(stillRunning.ciAccessibilityLabel == "CI: running")
    }

    // AC6, AC17
    @Test func readyOnlyForMyPublishedPullRequests() {
        let ok = checks(build(1, "A", .passed), ready: true)
        let r = row(ok)
        #expect(r.isReady)
        #expect(r.ciAccessibilityLabel == "CI: succeeded, ready to merge")
        #expect(row(checks(ready: true)).isReady)  // aucune policy CI : prête quand même
        #expect(!row(ok, pr: pr(1, author: me, draft: true)).isReady)
        #expect(!row(ok, pr: pr(1, author: me, conflict: true)).isReady)
        #expect(!row(checks(build(1, "A", .passed))).isReady)
        let review = row(ok, pr: pr(1), mine: false)
        #expect(!review.isReady)
        #expect(review.pipelines.count == 1)
    }
}

struct NotificationContentTests {
    private let links = WebLinks(org: org)
    private let tags = TagSettings(hidden: ["p1"])

    // AC16, AC30, AC32
    @Test func contents() {
        var p = pr(7, title: "[P1] Add retry", author: sarah)
        p.repositoryName = "payments-api"
        let review = NotificationContent.make(.reviewRequested(p), tags: tags, links: links)
        #expect(review.title == "Review Requested")
        #expect(review.body == "Add retry")
        #expect(review.subtitle == "payments-api · by Sarah Chen")
        #expect(review.url == links.pullRequest(p))
        #expect(review.threadID == "pr-7")

        let assigned = NotificationContent.make(.workItemAssigned(wi(42)), tags: tags, links: links)
        #expect(assigned.title == "Work Item Assigned")
        #expect(assigned.body == "#42 WI 42")
        #expect(assigned.url.absoluteString == "https://dev.azure.com/contoso/Billing/_workitems/edit/42")

        let vote = NotificationContent.make(
            .prVote(p, reviewer: priya, vote: .waitingForAuthor), tags: tags, links: links)
        #expect(vote.title == "Priya Natarajan voted Waiting for Author")

        let reply = NotificationContent.make(
            .prComment(p, author: priya, text: "Can we stream rows?\nsecond line", isReply: true), tags: tags,
            links: links)
        #expect(reply.title == "Priya Natarajan replied")
        #expect(reply.subtitle == "“Can we stream rows?”")

        let wiComment = NotificationContent.make(
            .workItemComment(wi(42), author: priya, text: String(repeating: "a", count: 200)), tags: tags, links: links)
        #expect(wiComment.title == "Priya Natarajan commented on #42")
        #expect(wiComment.subtitle?.count == 122)

        // AC7, AC10, AC11
        let failed = NotificationContent.make(
            .ciFailed(p, pipeline: "PR-Build", isOptional: false), tags: tags, links: links)
        #expect(failed.title == "CI Failed")
        #expect(failed.subtitle == "PR-Build")
        #expect(failed.body == "Add retry")
        #expect(failed.url == links.pullRequest(p))
        #expect(failed.threadID == "pr-7")
        let optional = NotificationContent.make(
            .ciFailed(p, pipeline: "Lint", isOptional: true), tags: tags, links: links)
        #expect(optional.subtitle == "Lint · optional")
        let ready = NotificationContent.make(.readyToMerge(p), tags: tags, links: links)
        #expect(ready.title == "Ready to Merge")
        #expect(ready.subtitle == "payments-api")
        #expect(ready.body == "Add retry")
        #expect(ready.threadID == "pr-7")
    }
}
