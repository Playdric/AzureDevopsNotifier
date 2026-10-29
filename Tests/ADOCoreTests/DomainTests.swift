import Foundation
import Testing

@testable import ADOCore

struct TitleCleanerTests {
    private let title = "[Backend][Hotfix] Fix [SSO] login"

    // AC32
    @Test func removesOnlyCheckedTagsAnywhere() {
        let settings = TagSettings(hidden: ["hotfix", "sso"])
        #expect(TitleCleaner.clean(title, settings: settings) == "[Backend] Fix login")
        #expect(TitleCleaner.clean(title, settings: TagSettings(hidden: ["hotfix"])) == "[Backend] Fix [SSO] login")
    }

    // AC33
    @Test func hideAllRemovesUnknownTags() {
        #expect(TitleCleaner.clean(title, settings: TagSettings(hideAll: true)) == "Fix login")
        #expect(TitleCleaner.clean("[Never seen] x", settings: TagSettings(hideAll: true)) == "x")
    }

    // AC34
    @Test(arguments: ["[HOTFIX] Fix", "[ Hotfix ] Fix", "[hotfix]Fix"])
    func matchingIgnoresCaseAndSpaces(input: String) {
        #expect(TitleCleaner.clean(input, settings: TagSettings(hidden: ["hotfix"])) == "Fix")
    }

    // AC35
    @Test func tagOnlyTitleFallsBackToOriginal() {
        #expect(TitleCleaner.clean("[WIP]", settings: TagSettings(hidden: ["wip"])) == "[WIP]")
        #expect(TitleCleaner.clean(" [WIP] - ", settings: TagSettings(hideAll: true)) == " [WIP] - ")
    }

    @Test(arguments: [
        ("[Mobile] - Write migration", "Write migration"),
        ("Write migration | [Mobile]", "Write migration"),
        ("[Mobile]: Write   migration", "Write migration"),
    ])
    func trimsEdgeSeparators(input: String, expected: String) {
        #expect(TitleCleaner.clean(input, settings: TagSettings(hidden: ["mobile"])) == expected)
    }

    @Test func untouchedWhenNothingRemoved() {
        #expect(TitleCleaner.clean("Fix:  login - ", settings: TagSettings(hidden: ["x"])) == "Fix:  login - ")
    }

    // Cas limites : crochets non fermés, imbriqués, vides.
    @Test(arguments: ["[WIP Fix login", "[[x]] Fix", "[] Fix", "[ ] Fix", "Fix ]oops["])
    func malformedBracketsAreNotTags(input: String) {
        #expect(TitleCleaner.tags(in: input).isEmpty)
        #expect(TitleCleaner.clean(input, settings: TagSettings(hideAll: true)) == input)
    }

    @Test func indexLikeBracketIsATag() {
        #expect(TitleCleaner.tags(in: "Fix array[0] bug").map(\.text) == ["0"])
        #expect(TitleCleaner.clean("Fix array[0] bug", settings: TagSettings()) == "Fix array[0] bug")
    }
}

struct TagCatalogTests {
    private let titles = [
        "[Backend][Hotfix] Fix login", "[backend] Refactor", "[Hotfix] Crash", "[Hotfix][Hotfix] twice", "No tag",
    ]

    // AC31
    @Test func detectsTagsWithTitleCounts() {
        let detected = TagCatalog.detect(in: titles)
        #expect(detected["backend"]?.count == 2)
        #expect(detected["backend"]?.display == "Backend")
        #expect(detected["hotfix"]?.count == 3)
        #expect(detected.count == 2)
    }

    // AC37
    @Test func newTagsAreKnownButVisible() {
        var settings = TagSettings(hidden: ["backend"], known: ["backend": "Backend"])
        TagCatalog.merge(titles + ["[P1] Urgent"], into: &settings)
        #expect(settings.known["p1"] == "P1")
        #expect(!settings.isHidden("P1"))
        #expect(settings.known["backend"] == "Backend")
    }

    // AC38
    @Test func choiceKeptWhenTagNoLongerSeen() {
        let settings = TagSettings(hidden: ["legacy"], known: ["legacy": "Legacy"])
        let entries = TagCatalog.entries(titles: titles, settings: settings)
        let legacy = entries.first { $0.key == "legacy" }
        #expect(legacy?.count == 0)
        #expect(legacy?.isHidden == true)
        #expect(entries.map(\.display) == ["Backend", "Hotfix", "Legacy"])
        #expect(TitleCleaner.clean("[Legacy] back", settings: settings) == "back")
    }

    @Test func hideAllMarksEveryEntry() {
        let entries = TagCatalog.entries(titles: titles, settings: TagSettings(hideAll: true))
        #expect(entries.allSatisfy { $0.isHidden })
    }
}

struct StateMenuTests {
    // AC7
    @Test func optionsExcludeCurrentAndHidden() {
        let options = StateMenu.options(for: wi(1, state: "Active"), types: types, hidden: ["Blocked"])
        #expect(options.map(\.name) == ["New", "Resolved", "Closed"])
    }

    // AC21
    @Test func hiddenStateRemovedForEveryType() {
        let bug = StateMenu.options(for: wi(1, type: "Bug", state: "New"), types: types, hidden: ["Blocked"])
        let story = StateMenu.options(for: wi(2, type: "User Story", state: "New"), types: types, hidden: ["Blocked"])
        #expect(!bug.contains { $0.name == "Blocked" })
        #expect(!story.contains { $0.name == "Blocked" })
    }

    // AC23
    @Test func eachProcessHasItsOwnStates() {
        let pbi = StateMenu.options(
            for: wi(3, type: "Product Backlog Item", state: "New", project: "Mobile"), types: types, hidden: [])
        #expect(pbi.map(\.name) == ["Approved", "Committed", "Done", "Removed"])
    }

    @Test func allHiddenGivesEmptyMenu() {
        let hidden: Set = ["New", "Active", "Resolved", "Closed", "Blocked"]
        #expect(StateMenu.options(for: wi(1), types: types, hidden: hidden).isEmpty)
    }

    // AC24 + état inconnu du process
    @Test func openness() {
        #expect(StateMenu.isOpen(wi(1, state: "Active"), types: types))
        #expect(!StateMenu.isOpen(wi(1, state: "Closed"), types: types))
        #expect(!StateMenu.isOpen(wi(1, type: "User Story", state: "Removed"), types: types))
        #expect(StateMenu.isOpen(wi(1, state: "Renamed Old State"), types: types))
        #expect(StateMenu.category(of: wi(1, state: "Renamed Old State"), in: types) == nil)
    }

    @Test func closedEverywhereSkipsAmbiguousNames() {
        var mixed = types
        mixed["Other"] = ["Task": WorkItemType(name: "Task", states: [StateDef(name: "Done", category: .inProgress)])]
        #expect(StateMenu.closedEverywhere(types) == ["Closed", "Done", "Removed"])
        #expect(StateMenu.closedEverywhere(mixed) == ["Closed", "Removed"])
    }

    // UC10
    @Test func catalogUnionsNamesWithCategories() {
        var mixed = types
        mixed["Other"] = ["Task": WorkItemType(name: "Task", states: [StateDef(name: "Done", category: .inProgress)])]
        let entries = StateCatalog.entries(mixed)
        #expect(
            entries.map(\.name) == [
                "Active", "Approved", "Blocked", "Closed", "Committed", "Done", "New", "Removed", "Resolved",
            ])
        #expect(Set(entries.first { $0.name == "Done" }!.categories) == [.completed, .inProgress])
    }
}

struct MuteTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    @Test func presets() throws {
        let now = try Date("2026-10-28T14:42:00+01:00", strategy: .iso8601)
        let tomorrow = try Date("2026-10-29T09:00:00+01:00", strategy: .iso8601)
        let oneHour = try MutePreset.oneHour.state(now: now)
        let morning = try MutePreset.untilTomorrowMorning.state(now: now, calendar: calendar)
        let forever = try MutePreset.indefinitely.state(now: now)
        #expect(oneHour == .until(now.addingTimeInterval(3600)))
        #expect(morning == .until(tomorrow))
        #expect(forever == .indefinitely)
    }

    @Test func pastDateRefused() {
        #expect(throws: MutePreset.DateInPast.self) { try MutePreset.until(t0).state(now: t0) }
        #expect(throws: MutePreset.DateInPast.self) { try MutePreset.until(t0.addingTimeInterval(-1)).state(now: t0) }
    }

    // AC25, AC26
    @Test func gateBlocksDuringMuteOnly() {
        let events: [NotifiableEvent] = [.workItemAssigned(wi(1))]
        let mute = MuteState.until(t0.addingTimeInterval(60))
        #expect(NotificationGate.filter(events, mute: mute, now: t0).isEmpty)
        #expect(NotificationGate.filter(events, mute: mute, now: t0.addingTimeInterval(60)) == events)
        #expect(NotificationGate.filter(events, mute: .indefinitely, now: .distantFuture).isEmpty)
        #expect(NotificationGate.filter(events, mute: .off, now: t0) == events)
    }

    // Fin de sourdine pendant la veille → levée au réveil.
    @Test func expiredMuteNormalizesToOff() {
        let mute = MuteState.until(t0)
        #expect(mute.normalized(at: t0.addingTimeInterval(-1)) == mute)
        #expect(mute.normalized(at: t0.addingTimeInterval(3600 * 10)) == .off)
    }
}

struct NotificationGateTests {
    private func draft(_ id: Int, author: Identity = sarah) -> PullRequest {
        var p = pr(id, author: author)
        p.isDraft = true
        return p
    }

    private func prefs(
        notify: Bool, draftsReview: Bool = true, draftsMine: Bool = true, states: Set<String> = ["Resolved"]
    )
        -> Preferences
    {
        var p = Preferences()
        p.notifyHiddenItems = notify
        p.hideDraftsToReview = draftsReview
        p.hideDraftsMine = draftsMine
        p.listHiddenStates = states
        return p
    }

    private var hiddenEvents: [NotifiableEvent] {
        [
            .reviewRequested(draft(1)),
            .prComment(draft(2, author: me), author: priya, text: "c", isReply: false),
            .prVote(draft(2, author: me), reviewer: priya, vote: .approved),
            .workItemAssigned(wi(3, state: "Resolved")),
            .workItemComment(wi(3, state: "Resolved"), author: priya, text: "c"),
        ]
    }

    private var visibleEvents: [NotifiableEvent] {
        [
            .reviewRequested(pr(4)),
            .prVote(pr(5, author: me), reviewer: priya, vote: .rejected),
            .workItemAssigned(wi(6, state: "Active")),
        ]
    }

    // AC43, AC45, AC46
    @Test func defaultNotifiesHiddenItems() {
        let events = hiddenEvents + visibleEvents
        #expect(NotificationGate.filter(events, prefs: prefs(notify: true), now: t0) == events)
    }

    // AC50, AC51, AC52
    @Test func disabledDropsOnlyHiddenItems() {
        let events = hiddenEvents + visibleEvents
        #expect(NotificationGate.filter(events, prefs: prefs(notify: false), now: t0) == visibleEvents)
    }

    // AC54
    @Test func draftsNotifiedWhenDraftFiltersOff() {
        let p = prefs(notify: false, draftsReview: false, draftsMine: false, states: [])
        #expect(NotificationGate.filter(hiddenEvents, prefs: p, now: t0) == hiddenEvents)
    }

    @Test func muteStillWins() {
        var p = prefs(notify: true)
        p.mute = .indefinitely
        #expect(NotificationGate.filter(visibleEvents, prefs: p, now: t0).isEmpty)
    }

    // AC53 : aucun rattrapage quand l'élément redevient visible.
    @Test func noCatchUpWhenItemBecomesVisible() {
        let p = prefs(notify: false)
        func thread(_ ids: [Int]) -> [PRThread] {
            [PRThread(id: 1, comments: ids.map { Comment(id: $0, author: priya, text: "c\($0)") })]
        }
        let mineDraft = draft(9, author: me)
        var minePublished = mineDraft
        minePublished.isDraft = false

        let s1 = snap(toReview: [draft(1)], myPRs: [mineDraft], threads: [9: thread([])])
        let s2 = snap(toReview: [draft(1)], myPRs: [mineDraft], threads: [9: thread([1])])
        var published = pr(1)
        published.isDraft = false
        let s3 = snap(toReview: [published], myPRs: [minePublished], threads: [9: thread([1])])
        let s4 = snap(toReview: [published], myPRs: [minePublished], threads: [9: thread([1, 2])])

        let duringHidden = EventDiffer.diff(old: s1, new: s2)
        #expect(duringHidden.count == 1)
        #expect(NotificationGate.filter(duringHidden, prefs: p, now: t0).isEmpty)
        #expect(EventDiffer.diff(old: s2, new: s3).isEmpty)
        #expect(
            NotificationGate.filter(EventDiffer.diff(old: s3, new: s4), prefs: p, now: t0)
                == [.prComment(minePublished, author: priya, text: "c2", isReply: true)])
    }
}
