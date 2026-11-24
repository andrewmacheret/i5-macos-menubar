import Foundation

/// Seattle time helpers. The lanes run on Seattle time no matter where the Mac is.
public enum Seattle {
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }()

    public static func day(of date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func time(of date: Date) -> TimeOfDay {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(c.hour!, c.minute!)
    }

    /// The moment a Seattle clock shows `time` on `day`. On daylight saving days a skipped
    /// time like 2:30 AM moves an hour later, and a repeated one uses the first time around.
    public static func date(_ day: DayKey, _ time: TimeOfDay) -> Date? {
        guard let midnight = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        else { return nil }
        if time.minutes >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: midnight) }
        // Count from midnight, then undo any clock change since. Seattle changes clocks at 2 AM,
        // never at midnight.
        let guess = midnight.addingTimeInterval(Double(time.minutes * 60))
        let change = timeZone.secondsFromGMT(for: guess) - timeZone.secondsFromGMT(for: midnight)
        let fixed = guess.addingTimeInterval(Double(-change))
        // If the fix lands on the other side of the change, the clock skipped this time.
        // Keep the guess, which is an hour later.
        return timeZone.secondsFromGMT(for: fixed) == timeZone.secondsFromGMT(for: guess) ? fixed : guess
    }

    public static func isWeekend(_ day: DayKey) -> Bool {
        guard let d = date(day, .midnight) else { return false }
        return calendar.isDateInWeekend(d)
    }

    public static func daysBetween(_ a: DayKey, _ b: DayKey) -> Int {
        guard let da = date(a, .midnight), let db = date(b, .midnight) else { return .max / 2 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }
}

public struct Change: Hashable, Sendable {
    public var date: Date
    public var to: LaneStatus

    public init(date: Date, to: LaneStatus) {
        self.date = date
        self.to = to
    }
}

public struct Segment: Hashable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var status: LaneStatus
}

/// Works out the lane status at any moment from the schedule and its exceptions.
public struct Engine: Sendable {
    public var info: ExpressLanesInfo

    public init(info: ExpressLanesInfo) { self.info = info }

    public func status(at date: Date) -> LaneStatus {
        if closure(at: date) != nil { return .closed }
        let day = Seattle.day(of: date)
        let t = Seattle.time(of: date)
        return windows(for: day).first { $0.start <= t && t < $0.end }?.status ?? .closed
    }

    public func closure(at date: Date) -> Closure? {
        info.closures.first { $0.start <= date && date < $0.end }
    }

    /// The early closing time for a day, if it has a known one
    public func earlyCloseTime(on day: DayKey) -> TimeOfDay? {
        guard let t = info.earlyClose(on: day)?.time else { return nil }
        return t == .midnight ? .endOfDay : t
    }

    public func windows(for day: DayKey) -> [LaneWindow] {
        var list = Seattle.isWeekend(day) ? info.schedule.weekend : info.schedule.weekday
        if let cut = earlyCloseTime(on: day) {
            list = list.compactMap { w in
                if w.start >= cut { return nil }
                return LaneWindow(w.status, w.start, min(w.end, cut))
            }
        }
        return list
    }

    /// The next few times the status flips, looking up to `days` ahead.
    public func upcomingChanges(from now: Date, limit: Int = 5, days: Int = 8) -> [Change] {
        let start = Seattle.calendar.dateInterval(of: .minute, for: now)?.start ?? now
        var current = status(at: now)
        var out: [Change] = []
        for minute in 1...(days * 24 * 60) {
            let d = start.addingTimeInterval(Double(minute) * 60)
            let s = status(at: d)
            if s != current {
                out.append(Change(date: d, to: s))
                current = s
                if out.count == limit { break }
            }
        }
        return out
    }

    /// Colored runs across one Seattle day, for the timeline bar.
    /// Steps through real clock time and places each step by its Seattle wall time,
    /// so days with a daylight saving change still line up.
    public func segments(for day: DayKey) -> [Segment] {
        guard let midnight = Seattle.date(day, .midnight),
              let nextMidnight = Seattle.calendar.date(byAdding: .day, value: 1, to: midnight)
        else { return [] }
        var out: [Segment] = []
        var d = midnight
        while d < nextMidnight {
            let s = status(at: d)
            let t = Seattle.time(of: d)
            let stepEnd = TimeOfDay(minutes: min(t.minutes + 5, 24 * 60))
            if let last = out.last, last.status == s, last.end <= t {
                out[out.count - 1].end = stepEnd
            } else if out.last?.end ?? .midnight > t {
                // Fall back repeats an hour. Skip the repeat.
            } else {
                out.append(Segment(start: t, end: stepEnd, status: s))
            }
            d = d.addingTimeInterval(5 * 60)
        }
        return out
    }

    public func upcomingEarlyCloses(from now: Date, limit: Int = 6) -> [EarlyClose] {
        let today = Seattle.day(of: now)
        let time = Seattle.time(of: now)
        let upcoming = info.earlyCloses.filter { e in
            e.day > today || (e.day == today && (e.time.map { time < $0 } ?? true))
        }
        return Array(upcoming.prefix(limit))
    }

    public func upcomingClosures(from now: Date) -> [Closure] {
        info.closures.filter { $0.end > now }.sorted { $0.start < $1.start }
    }
}
