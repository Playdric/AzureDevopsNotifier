import Foundation

public enum StateMenu {
    public static func type(of wi: WorkItem, in types: TypeCatalog) -> WorkItemType? {
        types[wi.projectName]?[wi.typeName]
    }

    /// Catégorie de l'état courant ; `nil` si l'état n'existe plus dans le process.
    public static func category(of wi: WorkItem, in types: TypeCatalog) -> StateCategory? {
        type(of: wi, in: types)?.states.first { $0.name == wi.state }?.category
    }

    /// États proposés : états du type − masqués − état courant (AC7, AC21, AC23).
    public static func options(for wi: WorkItem, types: TypeCatalog, hidden: Set<String>) -> [StateDef] {
        (type(of: wi, in: types)?.states ?? []).filter { $0.name != wi.state && !hidden.contains($0.name) }
    }

    /// WI encore ouvert : état courant hors catégories Completed / Removed. État inconnu → ouvert.
    public static func isOpen(_ wi: WorkItem, types: TypeCatalog) -> Bool {
        !(category(of: wi, in: types)?.isClosed ?? false)
    }

    /// Noms d'états fermés dans tous les types qui les définissent : exclus dès la requête WIQL.
    public static func closedEverywhere(_ types: TypeCatalog) -> Set<String> {
        var closed = Set<String>()
        var open = Set<String>()
        for state in types.values.flatMap(\.values).flatMap(\.states) {
            if state.category.isClosed { closed.insert(state.name) } else { open.insert(state.name) }
        }
        return closed.subtracting(open)
    }
}

public enum StateCatalog {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var name: String
        public var categories: [StateCategory]
        public var id: String { name }
    }

    /// Union des noms d'états de tous les types × projets suivis, triée (UC10).
    public static func entries(_ types: TypeCatalog) -> [Entry] {
        var byName: [String: [StateCategory]] = [:]
        for state in types.values.flatMap(\.values).flatMap(\.states)
        where byName[state.name]?.contains(state.category) != true {
            byName[state.name, default: []].append(state.category)
        }
        return byName.map { Entry(name: $0.key, categories: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
