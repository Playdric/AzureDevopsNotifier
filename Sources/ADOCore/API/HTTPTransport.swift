import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum ADOError: Error, Equatable, Sendable {
    /// PAT invalide, expiré ou scopes insuffisants.
    case unauthorized
    case network(String)
    case notFound
    case rateLimited
    /// Erreur renvoyée par ADO (message affiché tel quel, ex. règle de transition).
    case server(status: Int, message: String)
    case decoding(String)

    public var message: String {
        switch self {
        case .unauthorized:
            "The personal access token was rejected. Check that it hasn't expired and has the required scopes."
        case .network(let detail): "Can't reach Azure DevOps (\(detail))."
        case .notFound: "Not found or not accessible."
        case .rateLimited: "Azure DevOps is throttling requests. Retrying later."
        case .server(_, let message): message
        case .decoding: "Unexpected response from Azure DevOps."
        }
    }

    static func wrap(_ error: Error) -> ADOError {
        if let ado = error as? ADOError { return ado }
        if let url = error as? URLError { return .network(url.localizedDescription) }
        return .network(String(describing: error))
    }
}
