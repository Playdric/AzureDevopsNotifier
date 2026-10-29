import Foundation

/// Éléments masqués par les filtres d'affichage. Partagé par le panneau et les notifications (UC14).
public struct DisplayFilter: Sendable {
    public let prefs: Preferences

    public init(prefs: Preferences) {
        self.prefs = prefs
    }

    public func hides(review pr: PullRequest) -> Bool {
        prefs.hideDraftsToReview && pr.isDraft
    }

    public func hides(mine pr: PullRequest) -> Bool {
        prefs.hideDraftsMine && pr.isDraft
    }

    public func hides(_ wi: WorkItem) -> Bool {
        prefs.listHiddenStates.contains(wi.state)
    }

    /// Élément concerné masqué, selon son état dans le snapshot qui a produit l'événement.
    public func hides(_ event: NotifiableEvent) -> Bool {
        switch event {
        case .reviewRequested(let pr): hides(review: pr)
        case .prComment(let pr, _, _, _), .prVote(let pr, _, _): hides(mine: pr)
        case .workItemAssigned(let wi), .workItemComment(let wi, _, _): hides(wi)
        }
    }
}
