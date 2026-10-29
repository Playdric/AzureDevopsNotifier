import Foundation

/// URL d'organisation Azure DevOps cloud : `https://dev.azure.com/<org>` ou `https://<org>.visualstudio.com`.
public struct OrgURL: Hashable, Sendable, Codable, CustomStringConvertible {
    public let base: URL
    public let name: String

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let comps = URLComponents(string: text), comps.scheme?.lowercased() == "https",
            let host = comps.host?.lowercased()
        else { return nil }
        let segments = comps.path.split(separator: "/").map(String.init)

        if host == "dev.azure.com" {
            guard let org = segments.first, !org.isEmpty else { return nil }
            name = org
            base = URL(string: "https://dev.azure.com/\(org)")!
        } else if host.hasSuffix(".visualstudio.com") {
            let org = String(host.dropLast(".visualstudio.com".count))
            guard !org.isEmpty, !org.contains(".") else { return nil }
            name = org
            base = URL(string: "https://\(org).visualstudio.com")!
        } else {
            return nil
        }
    }

    public var description: String { base.absoluteString }
}
