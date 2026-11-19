import Foundation

public enum LaneStatus: String, Codable, Sendable, CaseIterable {
    case northbound, southbound, closed, unknown

    public var title: String {
        switch self {
        case .northbound: "Northbound"
        case .southbound: "Southbound"
        case .closed: "Closed"
        case .unknown: "Unknown"
        }
    }

    public var letter: String {
        switch self {
        case .northbound: "N"
        case .southbound: "S"
        case .closed: "✕"
        case .unknown: "?"
        }
    }

    public var isOpen: Bool { self == .northbound || self == .southbound }
}

/// Minutes since midnight, 0...1440.
public struct TimeOfDay: Comparable, Hashable, Codable, Sendable {
    public var minutes: Int

    public init(minutes: Int) { self.minutes = minutes }
    public init(_ hour: Int, _ minute: Int = 0) { minutes = hour * 60 + minute }

    public static let midnight = TimeOfDay(minutes: 0)
    public static let endOfDay = TimeOfDay(minutes: 24 * 60)

    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutes < b.minutes }

    /// "5 AM", "11:15 AM", "Midnight"
    public var label: String {
        let m = minutes % (24 * 60)
        if m == 0 { return "Midnight" }
        if m == 12 * 60 { return "Noon" }
        let h = m / 60, mm = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        return mm == 0 ? "\(h12) \(ampm)" : String(format: "%d:%02d %@", h12, mm, ampm)
    }
}

/// An open window. Any time not covered by a window is closed.
public struct LaneWindow: Hashable, Codable, Sendable {
    public var status: LaneStatus
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(_ status: LaneStatus, _ start: TimeOfDay, _ end: TimeOfDay) {
        self.status = status
        self.start = start
        self.end = end
    }
}

public struct WeeklySchedule: Hashable, Codable, Sendable {
    public var weekday: [LaneWindow]
    public var weekend: [LaneWindow]

    public init(weekday: [LaneWindow], weekend: [LaneWindow]) {
        self.weekday = weekday
        self.weekend = weekend
    }

    /// The schedule WSDOT posted as of Nov 2026. Used when the page can't be read.
    public static let builtIn = WeeklySchedule(
        weekday: [
            LaneWindow(.southbound, TimeOfDay(5), TimeOfDay(11)),
            LaneWindow(.northbound, TimeOfDay(11, 15), TimeOfDay(23)),
        ],
        weekend: [
            LaneWindow(.southbound, TimeOfDay(8), TimeOfDay(13, 30)),
            LaneWindow(.northbound, TimeOfDay(13, 45), TimeOfDay(23)),
        ]
    )
}

/// A calendar day in Seattle time.
public struct DayKey: Comparable, Hashable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// A full closure over a date range, like a weekend-long closure.
public struct Closure: Hashable, Codable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date

    public init(title: String, start: Date, end: Date) {
        self.title = title
        self.start = start
        self.end = end
    }
}

/// The days something applies to. `last == nil` means it has no end date.
public struct DayRange: Hashable, Codable, Sendable {
    public var first: DayKey
    public var last: DayKey?

    public init(first: DayKey, last: DayKey?) {
        self.first = first
        self.last = last
    }

    public func contains(_ day: DayKey) -> Bool {
        first <= day && (last.map { day <= $0 } ?? true)
    }

    public func isOver(before today: DayKey) -> Bool {
        last.map { $0 < today } ?? false
    }
}

public struct SpecialEvent: Hashable, Codable, Sendable {
    public var title: String
    public var detail: String
    public var link: URL?
    /// Days the event mentions. Nil when it has no dates we could read.
    public var days: DayRange?
    /// Set when we could read exact start and end times for a full closure.
    public var closure: Closure?

    public init(title: String, detail: String, link: URL?, days: DayRange? = nil, closure: Closure? = nil) {
        self.title = title
        self.detail = detail
        self.link = link
        self.days = days
        self.closure = closure
    }
}

public struct Advisory: Hashable, Codable, Sendable {
    public var text: String
    public var link: URL?
    /// Days the notice mentions. Nil when it has no dates we could read.
    public var days: DayRange?

    public init(text: String, link: URL?, days: DayRange?) {
        self.text = text
        self.link = link
        self.days = days
    }

    /// True when the notice only talks about days that are already over.
    public func isOver(before today: DayKey) -> Bool {
        days?.isOver(before: today) ?? false
    }
}

public struct EarlyClose: Hashable, Codable, Sendable {
    public var day: DayKey
    /// Nil when the page didn't say what time
    public var time: TimeOfDay?

    public init(day: DayKey, time: TimeOfDay?) {
        self.day = day
        self.time = time
    }
}

public struct ExpressLanesInfo: Hashable, Codable, Sendable {
    public var schedule: WeeklySchedule
    /// False when the page's schedule couldn't be parsed and the built-in one is used.
    public var scheduleFromPage: Bool
    public var earlyCloses: [EarlyClose]
    public var events: [SpecialEvent]
    public var advisories: [Advisory]
    /// Bits of the page that looked important but couldn't be read
    public var warnings: [String]

    public init(
        schedule: WeeklySchedule = .builtIn,
        scheduleFromPage: Bool = false,
        earlyCloses: [EarlyClose] = [],
        events: [SpecialEvent] = [],
        advisories: [Advisory] = [],
        warnings: [String] = []
    ) {
        self.schedule = schedule
        self.scheduleFromPage = scheduleFromPage
        self.earlyCloses = earlyCloses
        self.events = events
        self.advisories = advisories
        self.warnings = warnings
    }

    public var closures: [Closure] { events.compactMap(\.closure) }

    public func earlyClose(on day: DayKey) -> EarlyClose? {
        earlyCloses.first { $0.day == day }
    }

    public static let builtIn = ExpressLanesInfo()
}

public enum Sources {
    public static let expressLanes = URL(string: "https://wsdot.wa.gov/travel/roads-bridges/express-lanes")!
    public static let reviveI5 = URL(string: "https://wsdot.wa.gov/construction-planning/search-projects/revive-i-5-preserving-vital-freeway")!
    public static let travelMap = URL(string: "https://wsdot.com/travel/real-time/map/")!
    public static let wsdotTrafficX = URL(string: "https://x.com/wsdot_traffic")!
}
