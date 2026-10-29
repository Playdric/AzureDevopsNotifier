import Foundation
import Synchronization
import Testing

@testable import ADOCore

struct EventDifferTests {
    private func reviewer(_ id: Identity, _ vote: Vote) -> Reviewer { Reviewer(identity: id, vote: vote) }
    private func thread(_ id: Int, _ comments: [(Int, Identity)], system: Bool = false) -> PRThread {
        PRThread(id: id, comments: comments.map { Comment(id: $0.0, author: $0.1, text: "c\($0.0)", isSystem: system) })
    }

    @Test func identicalSnapshotsProduceNothing() {
        let s = snap(toReview: [pr(1)], myPRs: [pr(2, author: me)], workItems: [wi(1)])
        #expect(EventDiffer.diff(old: s, new: s).isEmpty)
    }

    // AC10
    @Test func newWorkItemOnce() {
        let old = snap(workItems: [wi(1)])
        let new = snap(workItems: [wi(1), wi(2)])
        #expect(EventDiffer.diff(old: old, new: new) == [.workItemAssigned(wi(2))])
        #expect(EventDiffer.diff(old: new, new: new).isEmpty)
    }

    // AC11
    @Test func newReviewRequest() {
        let p = pr(5, reviewers: [reviewer(me, .none)])
        #expect(EventDiffer.diff(old: snap(), new: snap(toReview: [p])) == [.reviewRequested(p)])
    }

    // AC12, AC13
    @Test func newThreadAndReplyFromOthersOnly() {
        let mine = pr(9, author: me)
        let old = snap(myPRs: [mine], threads: [9: [thread(1, [(1, priya)])]])
        let new = snap(
            myPRs: [mine],
            threads: [
                9: [
                    thread(1, [(1, priya), (2, sarah), (3, me)]),
                    thread(2, [(1, sarah)]),
                    thread(3, [(1, me)]),
                    thread(4, [(1, sarah)], system: true),
                ]
            ])
        let events = EventDiffer.diff(old: old, new: new)
        #expect(
            events == [
                .prComment(mine, author: sarah, text: "c2", isReply: true),
                .prComment(mine, author: sarah, text: "c1", isReply: false),
            ])
    }

    // AC14
    @Test func voteChanges() {
        let before = pr(9, author: me, reviewers: [reviewer(priya, .none), reviewer(sarah, .approved)])
        let after = pr(
            9, author: me,
            reviewers: [reviewer(priya, .waitingForAuthor), reviewer(sarah, .none), reviewer(me, .approved)])
        let events = EventDiffer.diff(old: snap(myPRs: [before]), new: snap(myPRs: [after]))
        #expect(events == [.prVote(after, reviewer: priya, vote: .waitingForAuthor)])
    }

    // AC15
    @Test func workItemCommentsFromOthers() {
        let comments = [
            Comment(id: 3, author: priya, text: "new"), Comment(id: 2, author: me, text: "mine"),
            Comment(id: 1, author: sarah, text: "old"),
        ]
        let old = snap(workItems: [wi(1, comments: 1)])
        let new = snap(workItems: [wi(1, comments: 3)], wiComments: [1: comments])
        #expect(
            EventDiffer.diff(old: old, new: new) == [.workItemComment(wi(1, comments: 3), author: priya, text: "new")])
    }

    @Test func newItemsAbsorbTheirHistory() {
        let fresh = pr(9, author: me, reviewers: [reviewer(priya, .rejected)])
        let new = snap(myPRs: [fresh], threads: [9: [thread(1, [(1, priya)])]], workItems: [wi(1, comments: 4)])
        #expect(EventDiffer.diff(old: snap(), new: new) == [.workItemAssigned(wi(1, comments: 4))])
    }
}

struct SyncServiceTests {
    final class FakeADO: @unchecked Sendable {
        let snapshots: Mutex<[Result<Snapshot, ADOError>]>
        let refreshFlags = Mutex<[Bool]>([])
        let previousSeen = Mutex<[Snapshot?]>([])
        init(_ results: [Result<Snapshot, ADOError>]) { snapshots = Mutex(results) }

        var fetch: SyncService.Fetch {
            { previous, refresh in
                self.refreshFlags.withLock { $0.append(refresh) }
                self.previousSeen.withLock { $0.append(previous) }
                return try self.snapshots.withLock { $0.removeFirst() }.get()
            }
        }
    }

    // AC9, AC10, AC17
    @Test func baselineThenDiffAndErrorKeepsLastGood() async throws {
        let s1 = snap(workItems: [wi(1)])
        let s2 = snap(workItems: [wi(1), wi(2)])
        let fake = FakeADO([.success(s1), .failure(.network("offline")), .success(s2), .success(s2)])
        let sync = SyncService(interval: .seconds(120), fetch: fake.fetch, now: { t0 })

        guard case .baseline(let b) = await sync.cycle() else { Issue.record("baseline expected"); return }
        #expect(b == s1)
        guard case .failed(let error, let lastGood) = await sync.cycle() else {
            Issue.record("failure expected"); return
        }
        #expect(error == .network("offline"))
        #expect(lastGood == s1)
        guard case .updated(_, let events) = await sync.cycle() else { Issue.record("update expected"); return }
        #expect(events == [.workItemAssigned(wi(2))])
        guard case .updated(_, let none) = await sync.cycle() else { Issue.record("update expected"); return }
        #expect(none.isEmpty)
        // Après l'échec, le diff part bien du dernier snapshot réussi.
        #expect(fake.previousSeen.withLock { $0 } == [nil, s1, s1, s2])
    }

    @Test func typesRefreshedHourlyOrOnRequest() async {
        let clock = Mutex(t0)
        let fake = FakeADO(Array(repeating: .success(snap()), count: 4))
        let sync = SyncService(interval: .seconds(120), fetch: fake.fetch, now: { clock.withLock { $0 } })
        _ = await sync.cycle()
        clock.withLock { $0 = t0.addingTimeInterval(600) }
        _ = await sync.cycle()
        clock.withLock { $0 = t0.addingTimeInterval(3600) }
        _ = await sync.cycle()
        await sync.requestTypesRefresh()
        _ = await sync.cycle()
        #expect(fake.refreshFlags.withLock { $0 } == [true, false, true, true])
    }

    // AC18
    @Test func runSleepsConfiguredIntervalBetweenCycles() async {
        let fake = FakeADO(Array(repeating: .success(snap()), count: 3))
        let sleeps = Mutex<[Duration]>([])
        let sync = SyncService(
            interval: .seconds(180), fetch: fake.fetch,
            sleep: { duration in
                let count = sleeps.withLock {
                    $0.append(duration); return $0.count
                }
                if count == 3 { throw CancellationError() }
            })
        let outcomes = Mutex(0)
        await sync.run { _ in outcomes.withLock { $0 += 1 } }
        #expect(outcomes.withLock { $0 } == 3)
        #expect(sleeps.withLock { $0 } == [.seconds(180), .seconds(180), .seconds(180)])

        await sync.setInterval(.seconds(10))
        #expect(await sync.currentInterval == .seconds(60))
    }

    @Test func concurrentCycleIsSkipped() async {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let sync = SyncService(
            interval: .seconds(60),
            fetch: { _, _ in
                started.continuation.yield()
                for await _ in gate.stream { break }
                return snap()
            })
        async let first = sync.cycle()
        for await _ in started.stream { break }  // le 1er cycle est bien en vol
        let second = await sync.cycle()
        gate.continuation.yield()
        #expect(second == nil)
        #expect(await first != nil)
    }

    // Review #1 : synchro remplacée → résultat ignoré, pas d'erreur réseau.
    @Test func cancelledCycleReturnsNil() async {
        let sync = SyncService(interval: .seconds(60), fetch: { _, _ in throw CancellationError() })
        #expect(await sync.cycle() == nil)
    }
}
