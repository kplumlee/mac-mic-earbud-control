import Foundation
import EventKit

struct UpcomingMeeting: Equatable {
    let title: String
    let start: Date
    let joinURL: URL?
}

final class CalendarService {
    private let store = EKEventStore()

    /// Request read access to calendar events. Calls back on an arbitrary queue; hop to main in the caller if needed.
    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        store.requestAccess(to: .event) { granted, _ in completion(granted) }
    }

    /// The soonest upcoming event (starting now..+hours) across ALL calendars / ALL accounts, or nil.
    func nextMeeting(within hours: Int) -> UpcomingMeeting? {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) else { return nil }
        // calendars: nil => span EVERY calendar across EVERY connected account (iCloud, Google, Microsoft 365…)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && ($0.startDate ?? .distantFuture) >= now }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        guard let ev = events.first else { return nil }
        return UpcomingMeeting(title: ev.title ?? "Meeting",
                               start: ev.startDate ?? now,
                               joinURL: Self.joinURL(for: ev))
    }

    /// Find a video-call link in the event's url, location, or notes.
    static func joinURL(for ev: EKEvent) -> URL? {
        if let u = ev.url, Self.isMeetingURL(u.absoluteString) { return u }
        let haystacks = [ev.location, ev.notes].compactMap { $0 }
        let pattern = #"https://[^\s<>"']*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"']*"#
        for text in haystacks {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }

    static func isMeetingURL(_ s: String) -> Bool {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
        return hosts.contains { s.contains($0) }
    }
}
