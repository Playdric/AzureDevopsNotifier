import Foundation

/// Réglages de masquage des tags `[...]` de titre (UC12).
public struct TagSettings: Codable, Hashable, Sendable {
    public var hideAll: Bool
    /// Tags masqués, normalisés (voir `TitleCleaner.normalize`).
    public var hidden: Set<String>
    /// Tags déjà rencontrés : forme normalisée → forme affichée. Conservés même s'ils ne sont plus vus.
    public var known: [String: String]

    public init(hideAll: Bool = false, hidden: Set<String> = [], known: [String: String] = [:]) {
        self.hideAll = hideAll
        self.hidden = hidden
        self.known = known
    }

    public func isHidden(_ tag: String) -> Bool {
        hideAll || hidden.contains(TitleCleaner.normalize(tag))
    }
}

public enum TitleCleaner {
    public struct Tag: Equatable, Sendable {
        /// Texte entre crochets, espaces de bord retirés.
        public var text: String
        /// Plage `[...]` complète dans le titre.
        public var range: Range<String.Index>
    }

    public static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Tags `[x]` du titre : non vides, sans crochet imbriqué, ni collés à un autre crochet (`[[x]]` ignoré).
    public static func tags(in title: String) -> [Tag] {
        var result: [Tag] = []
        var i = title.startIndex
        while i < title.endIndex {
            guard title[i] == "[", i == title.startIndex || title[title.index(before: i)] != "[" else {
                i = title.index(after: i)
                continue
            }
            let contentStart = title.index(after: i)
            guard let close = title[contentStart...].firstIndex(where: { $0 == "[" || $0 == "]" }),
                title[close] == "]"
            else {
                i = contentStart
                continue
            }
            let after = title.index(after: close)
            let text = title[contentStart..<close].trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, after == title.endIndex || title[after] != "]" {
                result.append(Tag(text: text, range: i..<after))
            }
            i = after
        }
        return result
    }

    public static func clean(_ title: String, settings: TagSettings) -> String {
        let removed = tags(in: title).filter { settings.isHidden($0.text) }
        guard !removed.isEmpty else { return title }

        var out = title
        for tag in removed.reversed() {
            out.replaceSubrange(tag.range, with: " ")
        }
        out = out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let edge = CharacterSet(charactersIn: " -:|")
        out = out.trimmingCharacters(in: edge)
        return out.isEmpty ? title : out
    }
}

public enum TagCatalog {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var key: String
        public var display: String
        public var count: Int
        public var isHidden: Bool
        public var id: String { key }
    }

    /// Nombre de titres contenant chaque tag, par forme normalisée.
    public static func detect(in titles: [String]) -> [String: (display: String, count: Int)] {
        var result: [String: (display: String, count: Int)] = [:]
        for title in titles {
            var seenInTitle = Set<String>()
            for tag in TitleCleaner.tags(in: title) {
                let key = TitleCleaner.normalize(tag.text)
                guard seenInTitle.insert(key).inserted else { continue }
                result[key, default: (tag.text, 0)].count += 1
            }
        }
        return result
    }

    /// Ajoute les tags nouvellement vus à `known` (visibles par défaut).
    public static func merge(_ titles: [String], into settings: inout TagSettings) {
        for (key, value) in detect(in: titles) where settings.known[key] == nil {
            settings.known[key] = value.display
        }
    }

    /// Lignes de Settings › Titles, triées.
    public static func entries(titles: [String], settings: TagSettings) -> [Entry] {
        let detected = detect(in: titles)
        var keys = Set(settings.known.keys)
        keys.formUnion(detected.keys)
        return keys.map { key in
            Entry(
                key: key,
                display: settings.known[key] ?? detected[key]?.display ?? key,
                count: detected[key]?.count ?? 0,
                isHidden: settings.hideAll || settings.hidden.contains(key)
            )
        }
        .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }
}
