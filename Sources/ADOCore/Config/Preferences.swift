import Foundation

public enum PanelWidth: String, Codable, Hashable, Sendable, CaseIterable {
    case standard, wide, extraWide

    public var points: Double {
        switch self {
        case .standard: 380
        case .wide: 480
        case .extraWide: 600
        }
    }

    public var label: String {
        switch self {
        case .standard: "Standard"
        case .wide: "Wide"
        case .extraWide: "Extra Wide"
        }
    }
}

/// Réglages non secrets. Le PAT est dans le Keychain (`SecretStore`), jamais ici.
public struct Preferences: Codable, Hashable, Sendable {
    public static let minRefreshMinutes = 1
    public static let refreshChoices = [1, 2, 5, 10, 15, 30]

    public var orgURL: OrgURL?
    public var me: Identity?
    public var projects: [Project] = []
    public var refreshMinutes: Int = 2
    public var hiddenStates: Set<String> = []
    public var tags = TagSettings()
    public var mute: MuteState = .off
    public var collapsedSections: Set<String> = []
    public var launchAtLogin = true
    /// États dont les WI sont masqués de la liste (affichage seul, notifications inchangées).
    public var listHiddenStates: Set<String> = []
    public var hideDraftsToReview = false
    public var hideDraftsMine = false
    public var panelWidth: PanelWidth = .standard
    public var wrapTitles = false
    /// Notifier les éléments masqués par les filtres d'affichage (UC14).
    public var notifyHiddenItems = true

    public init() {}

    /// Champ absent (réglages d'une version précédente) → valeur par défaut.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        orgURL = try c.decodeIfPresent(OrgURL.self, forKey: .orgURL)
        me = try c.decodeIfPresent(Identity.self, forKey: .me)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? d.projects
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        hiddenStates = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenStates) ?? d.hiddenStates
        tags = try c.decodeIfPresent(TagSettings.self, forKey: .tags) ?? d.tags
        mute = try c.decodeIfPresent(MuteState.self, forKey: .mute) ?? d.mute
        collapsedSections = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedSections) ?? d.collapsedSections
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        listHiddenStates = try c.decodeIfPresent(Set<String>.self, forKey: .listHiddenStates) ?? d.listHiddenStates
        hideDraftsToReview = try c.decodeIfPresent(Bool.self, forKey: .hideDraftsToReview) ?? d.hideDraftsToReview
        hideDraftsMine = try c.decodeIfPresent(Bool.self, forKey: .hideDraftsMine) ?? d.hideDraftsMine
        panelWidth = try c.decodeIfPresent(PanelWidth.self, forKey: .panelWidth) ?? d.panelWidth
        wrapTitles = try c.decodeIfPresent(Bool.self, forKey: .wrapTitles) ?? d.wrapTitles
        notifyHiddenItems = try c.decodeIfPresent(Bool.self, forKey: .notifyHiddenItems) ?? d.notifyHiddenItems
    }

    public var isConfigured: Bool { orgURL != nil && me != nil && !projects.isEmpty }

    public var refreshInterval: Duration {
        .seconds(60 * max(Self.minRefreshMinutes, refreshMinutes))
    }
}

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "preferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Preferences {
        guard let data = defaults.data(forKey: key),
            let prefs = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return prefs
    }

    public func save(_ prefs: Preferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key)
        }
    }
}
