import Foundation
import Testing

@testable import ADOCore

struct OrgURLTests {
    @Test(arguments: [
        ("https://dev.azure.com/contoso", "contoso", "https://dev.azure.com/contoso"),
        ("dev.azure.com/contoso/", "contoso", "https://dev.azure.com/contoso"),
        ("https://dev.azure.com/contoso/Billing/_git/x", "contoso", "https://dev.azure.com/contoso"),
        ("  https://contoso.visualstudio.com  ", "contoso", "https://contoso.visualstudio.com"),
    ])
    func parsesCloudURLs(raw: String, name: String, base: String) {
        let url = OrgURL(raw)
        #expect(url?.name == name)
        #expect(url?.base.absoluteString == base)
    }

    @Test(arguments: [
        "", "http://dev.azure.com/contoso", "https://dev.azure.com/", "https://example.com/contoso",
        "https://tfs.local/DefaultCollection", "https://a.b.visualstudio.com",
    ])
    func rejectsOthers(raw: String) {
        #expect(OrgURL(raw) == nil)
    }
}

struct WebLinksTests {
    // AC6
    @Test func pullRequestAndWorkItemURLs() {
        let links = WebLinks(org: org)
        var p = pr(42)
        p.projectName = "Data Warehouse"
        #expect(
            links.pullRequest(p).absoluteString
                == "https://dev.azure.com/contoso/Data%20Warehouse/_git/payments-api/pullrequest/42")
        #expect(links.workItem(wi(7)).absoluteString == "https://dev.azure.com/contoso/Billing/_workitems/edit/7")
        let legacy = WebLinks(org: OrgURL("https://contoso.visualstudio.com")!)
        #expect(legacy.workItem(wi(7)).absoluteString == "https://contoso.visualstudio.com/Billing/_workitems/edit/7")
    }
}

struct PreferencesTests {
    private func store() -> PreferencesStore {
        let name = "test-\(UUID())"
        return PreferencesStore(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func defaultsWhenEmpty() {
        let prefs = store().load()
        #expect(!prefs.isConfigured)
        #expect(prefs.refreshMinutes == 2)
        #expect(prefs.launchAtLogin)
    }

    // AC27, AC38
    @Test func roundTripKeepsMuteAndTags() {
        let s = store()
        var prefs = Preferences()
        prefs.orgURL = org
        prefs.me = me
        prefs.projects = [Project(id: "p1", name: "Billing")]
        prefs.mute = .until(t0)
        prefs.tags = TagSettings(hideAll: false, hidden: ["hotfix"], known: ["hotfix": "Hotfix"])
        prefs.hiddenStates = ["Blocked"]
        s.save(prefs)
        #expect(s.load() == prefs)
        #expect(s.load().isConfigured)
    }

    // AC47 + réglages enregistrés par la version précédente (sans les champs du lot 2).
    @Test func legacyJSONDecodesWithDefaults() throws {
        let legacy = Data(
            #"""
            {"orgURL":{"base":"https://dev.azure.com/contoso","name":"contoso"},"me":{"id":"u-me","displayName":"Cédric Nanteau"},
             "projects":[{"id":"p1","name":"Billing"}],"refreshMinutes":5,"hiddenStates":["Removed"],
             "tags":{"hideAll":false,"hidden":["p1"],"known":{"p1":"P1"}},"mute":{"off":{}},
             "collapsedSections":[],"launchAtLogin":false}
            """#.utf8)
        let prefs = try JSONDecoder().decode(Preferences.self, from: legacy)
        #expect(prefs.isConfigured)
        #expect(prefs.refreshMinutes == 5)
        #expect(prefs.tags.hidden == ["p1"])
        #expect(!prefs.launchAtLogin)
        #expect(prefs.panelWidth == .standard)
        #expect(prefs.listHiddenStates.isEmpty)
        #expect(!prefs.hideDraftsToReview && !prefs.hideDraftsMine && !prefs.wrapTitles)
        #expect(prefs.notifyHiddenItems)  // AC49
    }

    @Test func panelOptionsRoundTrip() {
        let s = store()
        var prefs = Preferences()
        prefs.panelWidth = .wide
        prefs.wrapTitles = true
        prefs.hideDraftsToReview = true
        prefs.listHiddenStates = ["Resolved"]
        s.save(prefs)
        #expect(s.load() == prefs)
        #expect(s.load().panelWidth.points == 480)
    }

    // AC3 : aucun secret dans les réglages persistés.
    @Test func encodedPreferencesHaveNoPATField() throws {
        var prefs = Preferences()
        prefs.orgURL = org
        let json = String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self)
        #expect(!json.lowercased().contains("pat"))
        #expect(!json.lowercased().contains("token"))
    }

    // AC18 : intervalle minimal 1 min.
    @Test func refreshIntervalIsClamped() {
        var prefs = Preferences()
        prefs.refreshMinutes = 0
        #expect(prefs.refreshInterval == .seconds(60))
        prefs.refreshMinutes = 5
        #expect(prefs.refreshInterval == .seconds(300))
    }
}

extension Tag {
    /// Touche le trousseau de session réel (déverrouillé requis).
    @Tag static var keychain: Self
}

@Suite(.tags(.keychain))
struct KeychainStoreTests {
    // AC3
    @Test func roundTripUpdateDelete() throws {
        let store = KeychainStore(service: "com.cedricnanteau.ado-notifier.tests")
        let account = "https://dev.azure.com/test-\(UUID())"
        defer { try? store.delete(account: account) }

        #expect(try store.read(account: account) == nil)
        try store.write("first-secret", account: account)
        #expect(try store.read(account: account) == "first-secret")
        try store.write("second-secret", account: account)
        #expect(try store.read(account: account) == "second-secret")
        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
    }
}
