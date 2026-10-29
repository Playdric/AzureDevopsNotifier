import Foundation

/// Texte d'une notification système : titre = événement, corps = élément.
public struct NotificationContent: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var body: String
    public var url: URL
    /// Regroupe les notifications d'un même élément.
    public var threadID: String

    public static func make(_ event: NotifiableEvent, tags: TagSettings, links: WebLinks) -> NotificationContent {
        func clean(_ title: String) -> String { TitleCleaner.clean(title, settings: tags) }
        func excerpt(_ text: String) -> String? {
            let line =
                text.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { return nil }
            return "“" + (line.count > 120 ? line.prefix(119) + "…" : line) + "”"
        }

        switch event {
        case .workItemAssigned(let wi):
            return NotificationContent(
                title: "Work Item Assigned", subtitle: nil, body: "#\(wi.id) \(clean(wi.title))",
                url: links.workItem(wi), threadID: "wi-\(wi.id)")
        case .reviewRequested(let pr):
            return NotificationContent(
                title: "Review Requested", subtitle: "\(pr.repositoryName) · by \(pr.author.displayName)",
                body: clean(pr.title), url: links.pullRequest(pr), threadID: "pr-\(pr.id)")
        case .prComment(let pr, let author, let text, let isReply):
            return NotificationContent(
                title: "\(author.displayName) \(isReply ? "replied" : "commented")", subtitle: excerpt(text),
                body: clean(pr.title), url: links.pullRequest(pr), threadID: "pr-\(pr.id)")
        case .prVote(let pr, let reviewer, let vote):
            return NotificationContent(
                title: "\(reviewer.displayName) voted \(vote.label)", subtitle: nil, body: clean(pr.title),
                url: links.pullRequest(pr), threadID: "pr-\(pr.id)")
        case .workItemComment(let wi, let author, let text):
            return NotificationContent(
                title: "\(author.displayName) commented on #\(wi.id)", subtitle: excerpt(text), body: clean(wi.title),
                url: links.workItem(wi), threadID: "wi-\(wi.id)")
        case .ciFailed(let pr, let pipeline, let isOptional):
            return NotificationContent(
                title: "CI Failed", subtitle: isOptional ? "\(pipeline) · optional" : pipeline, body: clean(pr.title),
                url: links.pullRequest(pr), threadID: "pr-\(pr.id)")
        case .readyToMerge(let pr):
            return NotificationContent(
                title: "Ready to Merge", subtitle: pr.repositoryName, body: clean(pr.title),
                url: links.pullRequest(pr), threadID: "pr-\(pr.id)")
        }
    }
}
