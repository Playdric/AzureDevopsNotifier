import Foundation

struct ListDTO<T: Decodable>: Decodable {
    var value: [T]
}

struct ErrorDTO: Decodable {
    var message: String
}

struct IdentityDTO: Decodable {
    var id: String
    var displayName: String

    var model: Identity { Identity(id: id, displayName: displayName) }
}

struct ConnectionDataDTO: Decodable {
    struct User: Decodable {
        var id: String
        var providerDisplayName: String
    }
    var authenticatedUser: User
}

struct ProjectDTO: Decodable {
    var id: String
    var name: String
}

struct PullRequestDTO: Decodable {
    struct Repository: Decodable {
        struct ProjectRef: Decodable { var name: String }
        var id: String
        var name: String
        var project: ProjectRef
    }
    struct ReviewerDTO: Decodable {
        var id: String
        var displayName: String
        var vote: Int
        var isContainer: Bool?
    }

    var pullRequestId: Int
    var title: String
    var isDraft: Bool?
    var creationDate: Date
    var createdBy: IdentityDTO
    var repository: Repository
    var reviewers: [ReviewerDTO]?

    var model: PullRequest {
        PullRequest(
            id: pullRequestId, title: title, projectName: repository.project.name, repositoryName: repository.name,
            author: createdBy.model, creationDate: creationDate, isDraft: isDraft ?? false,
            reviewers: (reviewers ?? []).map {
                Reviewer(
                    identity: Identity(id: $0.id, displayName: $0.displayName), vote: Vote(rawValue: $0.vote) ?? .none,
                    isContainer: $0.isContainer ?? false)
            })
    }
}

struct ThreadDTO: Decodable {
    struct CommentDTO: Decodable {
        var id: Int
        var author: IdentityDTO
        var content: String?
        var commentType: String?
        var isDeleted: Bool?
    }
    var id: Int
    var comments: [CommentDTO]
    var isDeleted: Bool?

    var model: PRThread {
        PRThread(
            id: id,
            comments: comments.filter { $0.isDeleted != true }.map {
                Comment(
                    id: $0.id, author: $0.author.model, text: $0.content ?? "", isSystem: $0.commentType == "system")
            })
    }
}

struct WorkItemTypeDTO: Decodable {
    struct StateDTO: Decodable {
        var name: String
        var category: String
    }
    var name: String
    var color: String?
    var states: [StateDTO]?

    var model: WorkItemType {
        WorkItemType(
            name: name, color: color,
            states: (states ?? []).map {
                StateDef(name: $0.name, category: StateCategory(rawValue: $0.category) ?? .inProgress)
            })
    }
}

struct WiqlResultDTO: Decodable {
    struct Ref: Decodable { var id: Int }
    var workItems: [Ref]
}

struct WorkItemsBatchBody: Encodable {
    var ids: [Int]
    var fields: [String]
    var errorPolicy: String
}

struct PatchOperation: Encodable {
    var op: String
    var path: String
    var value: String
}

struct WorkItemDTO: Decodable {
    struct Fields: Decodable {
        var title: String
        var type: String
        var state: String
        var project: String
        var commentCount: Int?

        enum CodingKeys: String, CodingKey {
            case title = "System.Title"
            case type = "System.WorkItemType"
            case state = "System.State"
            case project = "System.TeamProject"
            case commentCount = "System.CommentCount"
        }
    }
    var id: Int
    var fields: Fields

    var model: WorkItem {
        WorkItem(
            id: id, title: fields.title, typeName: fields.type, state: fields.state, projectName: fields.project,
            commentCount: fields.commentCount ?? 0)
    }
}

struct CommentListDTO: Decodable {
    struct CommentDTO: Decodable {
        var id: Int
        var text: String?
        var createdBy: IdentityDTO
    }
    var comments: [CommentDTO]
}

extension CommentListDTO.CommentDTO {
    /// Texte brut (les commentaires WI sont en HTML).
    var model: Comment {
        let plain = (text ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return Comment(id: id, author: createdBy.model, text: plain)
    }
}
