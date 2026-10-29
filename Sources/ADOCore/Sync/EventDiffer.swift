import Foundation

public enum NotifiableEvent: Hashable, Sendable {
    case workItemAssigned(WorkItem)
    case reviewRequested(PullRequest)
    case prComment(PullRequest, author: Identity, text: String, isReply: Bool)
    case prVote(PullRequest, reviewer: Identity, vote: Vote)
    case workItemComment(WorkItem, author: Identity, text: String)
    case ciFailed(PullRequest, pipeline: String, isOptional: Bool)
    case readyToMerge(PullRequest)
}

public enum EventDiffer {
    /// Événements survenus entre deux snapshots réussis. Un élément apparu dans `new` absorbe
    /// son historique (commentaires, votes) sans notification.
    public static func diff(old: Snapshot, new: Snapshot) -> [NotifiableEvent] {
        let me = new.me.id
        var events: [NotifiableEvent] = []

        let oldWIs = Dictionary(old.workItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for wi in new.workItems {
            guard let previous = oldWIs[wi.id] else {
                events.append(.workItemAssigned(wi))
                continue
            }
            let added = wi.commentCount - previous.commentCount
            guard added > 0 else { continue }
            for comment in (new.workItemComments[wi.id] ?? []).prefix(added)
            where comment.author.id != me && !comment.isSystem {
                events.append(.workItemComment(wi, author: comment.author, text: comment.text))
            }
        }

        let oldReview = Set(old.toReview.map(\.id))
        events += new.toReview.filter { !oldReview.contains($0.id) }.map(NotifiableEvent.reviewRequested)

        let oldMine = Dictionary(old.myPRs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for pr in new.myPRs {
            guard let previous = oldMine[pr.id] else { continue }
            events += votes(old: previous, new: pr, me: me)
            events += comments(old: old.threads[pr.id] ?? [], new: new.threads[pr.id] ?? [], pr: pr, me: me)
            events += checks(old: previous, new: pr, before: old.checks[pr.id], after: new.checks[pr.id])
        }
        return events
    }

    private static func votes(old: PullRequest, new: PullRequest, me: String) -> [NotifiableEvent] {
        let before = Dictionary(old.reviewers.map { ($0.identity.id, $0.vote) }, uniquingKeysWith: { a, _ in a })
        return new.reviewers.compactMap { reviewer in
            guard reviewer.identity.id != me, reviewer.vote != .none,
                reviewer.vote != before[reviewer.identity.id] ?? .none
            else { return nil }
            return .prVote(new, reviewer: reviewer.identity, vote: reviewer.vote)
        }
    }

    private static func comments(old: [PRThread], new: [PRThread], pr: PullRequest, me: String) -> [NotifiableEvent] {
        let oldThreads = Set(old.map(\.id))
        // Id de commentaire unique par thread seulement → clé thread/commentaire.
        let known = Set(old.flatMap { thread in thread.comments.map { "\(thread.id)/\($0.id)" } })
        var events: [NotifiableEvent] = []
        for thread in new {
            for comment in thread.comments
            where comment.author.id != me && !comment.isSystem && !known.contains("\(thread.id)/\(comment.id)") {
                let isReply = oldThreads.contains(thread.id) || comment.id != thread.comments.first?.id
                events.append(.prComment(pr, author: comment.author, text: comment.text, isReply: isReply))
            }
        }
        return events
    }

    /// Statut inconnu d'un côté (erreur API) : rien, pour ne pas notifier à tort (AC16).
    private static func checks(old: PullRequest, new: PullRequest, before: PRChecks?, after: PRChecks?)
        -> [NotifiableEvent]
    {
        guard let before, let after else { return [] }
        let previous = Dictionary(before.pipelines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var events: [NotifiableEvent] = after.pipelines.compactMap { pipeline in
            guard pipeline.status == .failed else { return nil }
            // Même build toujours en échec : déjà notifié. Nouveau build en échec : relance ratée.
            if let was = previous[pipeline.id], was.status == .failed, was.buildID == pipeline.buildID { return nil }
            return .ciFailed(new, pipeline: pipeline.name, isOptional: !pipeline.isRequired)
        }
        if new.isReady(after) && !old.isReady(before) { events.append(.readyToMerge(new)) }
        return events
    }
}
