import Foundation

/// Everything the popover and the badge show, worked out once.
public struct Snapshot: Sendable {
    public var now: Moment
    public var today: DayKey
    public var status: ServerStatus
    public var check: Assessment
    public var changes: [Change]
    public var next: Change?
    public var todaySegments: [DaySegment]
    public var tomorrowSegments: [DaySegment]
    public var tomorrowDoubts: [Doubt]
    /// Days in the next week with something the server can't vouch for
    public var doubtfulDays: Set<DayKey>

    public init(status: ServerStatus, now: Moment, refreshing: Bool = false) {
        let p = status.published
        let today = Seattle.day(now)
        let tomorrow = Seattle.addDays(today, 1)
        var doubtful = Set<DayKey>()
        if let p {
            for i in 0...7 {
                let d = Seattle.addDays(today, i)
                if !p.doubts(from: max(now, Seattle.startOfDay(d)), to: Seattle.startOfDay(Seattle.addDays(d, 1))).isEmpty {
                    doubtful.insert(d)
                }
            }
        }
        let changes = p?.upcomingChanges(from: now, limit: 4) ?? []
        let allUnknown = [DaySegment(start: 0, end: endOfDay, status: .unknown)]
        self.now = now
        self.today = today
        self.status = status
        check = Trust.assess(status, now: now, refreshing: refreshing)
        self.changes = changes
        next = changes.first
        todaySegments = p?.daySegments(today) ?? allUnknown
        tomorrowSegments = p?.daySegments(tomorrow) ?? allUnknown
        tomorrowDoubts = p?.doubts(from: Seattle.startOfDay(tomorrow), to: Seattle.startOfDay(Seattle.addDays(tomorrow, 1))) ?? []
        doubtfulDays = doubtful
    }

    /// "Closes", "Opens northbound", "Switches southbound"
    public static func verb(_ current: LaneStatus, _ to: LaneStatus) -> String {
        if to == .unknown { return "Schedule unknown" }
        if to == .closed { return "Closes" }
        if current == .closed || current == .unknown { return "Opens \(to.title.lowercased())" }
        return "Switches \(to.title.lowercased())"
    }

    /// "Closes at 9:00 PM"
    public var nextText: String {
        guard let next else { return "No changes coming up" }
        if next.to == .unknown { return "Schedule unknown after \(Format.when(next.at, now: now))" }
        return "\(Snapshot.verb(check.scheduled, next.to)) at \(Format.when(next.at, now: now))"
    }

    /// True when the lanes flip within 15 minutes
    public var changingSoon: Bool {
        guard let next else { return false }
        return next.to != .unknown && next.at - now <= 15 * 60_000
    }
}
