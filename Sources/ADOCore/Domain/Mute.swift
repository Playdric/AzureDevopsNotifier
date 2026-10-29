import Foundation

public enum MuteState: Codable, Hashable, Sendable {
    case off
    case until(Date)
    case indefinitely

    public func isActive(at now: Date) -> Bool {
        switch self {
        case .off: false
        case .until(let end): now < end
        case .indefinitely: true
        }
    }

    /// Sourdine échue → `.off` (fin pendant la veille comprise).
    public func normalized(at now: Date) -> MuteState {
        isActive(at: now) ? self : .off
    }
}

public enum MutePreset: Hashable, Sendable {
    case oneHour
    case untilTomorrowMorning
    case until(Date)
    case indefinitely

    public struct DateInPast: Error, Equatable {}

    public func state(now: Date, calendar: Calendar = .current) throws -> MuteState {
        switch self {
        case .oneHour:
            return .until(now.addingTimeInterval(3600))
        case .untilTomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return .until(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!)
        case .until(let date):
            guard date > now else { throw DateInPast() }
            return .until(date)
        case .indefinitely:
            return .indefinitely
        }
    }
}

public enum NotificationGate {
    /// Événements à notifier : aucun pendant la sourdine (jamais rattrapés ensuite).
    public static func filter(_ events: [NotifiableEvent], mute: MuteState, now: Date) -> [NotifiableEvent] {
        mute.isActive(at: now) ? [] : events
    }

    /// Sourdine, réglages CI, puis éléments masqués si « Notify for hidden items » est désactivé (UC14).
    public static func filter(_ events: [NotifiableEvent], prefs: Preferences, now: Date) -> [NotifiableEvent] {
        let audible = filter(events, mute: prefs.mute, now: now).filter { event in
            switch event {
            case .ciFailed: prefs.notifyCIFailures
            case .readyToMerge: prefs.notifyReadyToMerge
            default: true
            }
        }
        guard !prefs.notifyHiddenItems else { return audible }
        let display = DisplayFilter(prefs: prefs)
        return audible.filter { !display.hides($0) }
    }
}
