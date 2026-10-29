import Foundation

public enum CycleOutcome: Sendable {
    /// Premier cycle réussi : baseline, aucune notification (AC9).
    case baseline(Snapshot)
    case updated(Snapshot, [NotifiableEvent])
    /// Échec : le dernier snapshot réussi reste la référence (AC17).
    case failed(ADOError, lastGood: Snapshot?)
}

/// Boucle de polling : fetch, diff contre le dernier snapshot réussi, attente.
public actor SyncService {
    public typealias Fetch = @Sendable (_ previous: Snapshot?, _ refreshTypes: Bool) async throws -> Snapshot
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    public static let typesRefreshInterval: TimeInterval = 3600

    private let fetch: Fetch
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private var interval: Duration
    private var lastGood: Snapshot?
    private var lastTypesRefresh: Date?
    private var forceTypesRefresh = false
    private var inFlight = false

    public init(
        interval: Duration, fetch: @escaping Fetch,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.interval = max(interval, .seconds(60))
        self.fetch = fetch
        self.sleep = sleep
        self.now = now
    }

    public var currentInterval: Duration { interval }

    public func setInterval(_ value: Duration) {
        interval = max(value, .seconds(60))
    }

    /// Recharge les types WI au prochain cycle (ex. ouverture de Settings).
    public func requestTypesRefresh() {
        forceTypesRefresh = true
    }

    /// Un cycle ; `nil` si un cycle est déjà en cours (refresh manuel pendant le polling) ou s'il a été annulé.
    public func cycle() async -> CycleOutcome? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }

        let start = now()
        let refreshTypes =
            forceTypesRefresh
            || lastTypesRefresh.map { start.timeIntervalSince($0) >= Self.typesRefreshInterval } ?? true
        do {
            let snapshot = try await fetch(lastGood, refreshTypes)
            if refreshTypes {
                lastTypesRefresh = start
                forceTypesRefresh = false
            }
            defer { lastGood = snapshot }
            guard let previous = lastGood else { return .baseline(snapshot) }
            return .updated(snapshot, EventDiffer.diff(old: previous, new: snapshot))
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            return .failed(ADOError.wrap(error), lastGood: lastGood)
        }
    }

    /// Boucle jusqu'à annulation de la tâche appelante.
    public func run(onOutcome: @Sendable (CycleOutcome) async -> Void) async {
        while !Task.isCancelled {
            if let outcome = await cycle() { await onOutcome(outcome) }
            do { try await sleep(interval) } catch { return }
        }
    }
}
