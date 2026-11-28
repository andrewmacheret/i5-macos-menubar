import Foundation

// What the server publishes at GET /status. A Swift copy of i5-client/src/core/models.ts.
// Moments are epoch milliseconds. Days are Seattle calendar days like "2026-11-18".
// Decoding is forgiving: unknown fields are ignored and missing ones get a default,
// since the server adds fields over time.

/// Milliseconds since 1970
public typealias Moment = Int
/// Minutes since midnight, 0 to 1440
public typealias TimeOfDay = Int
/// A calendar day in Seattle, "YYYY-MM-DD". Sorts and compares as a string.
public typealias DayKey = String

public extension Date {
    var moment: Moment { Moment((timeIntervalSince1970 * 1000).rounded(.down)) }
    init(moment: Moment) { self.init(timeIntervalSince1970: Double(moment) / 1000) }
}

public let midnight: TimeOfDay = 0
public let endOfDay: TimeOfDay = 24 * 60

public func hm(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { hour * 60 + minute }

/// "5 AM", "11:15 AM", "Midnight"
public func timeLabel(_ t: TimeOfDay) -> String {
    let m = t % (24 * 60)
    if m == 0 { return "Midnight" }
    if m == 12 * 60 { return "Noon" }
    let h = m / 60, mm = m % 60
    let h12 = h % 12 == 0 ? 12 : h % 12
    let ampm = h < 12 ? "AM" : "PM"
    return mm == 0 ? "\(h12) \(ampm)" : String(format: "%d:%02d %@", h12, mm, ampm)
}

/// An enum that reads an unknown value as its fallback instead of failing
public protocol LenientEnum: RawRepresentable, Decodable, Sendable, Hashable where RawValue == String {
    static var fallback: Self { get }
}

public extension LenientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

public enum LaneStatus: String, LenientEnum, CaseIterable {
    case northbound, southbound, closed, unknown
    public static let fallback = LaneStatus.unknown

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

/// An open window. Any time not covered by a window is closed.
public struct LaneWindow: Hashable, Sendable {
    public var status: LaneStatus
    public var start: TimeOfDay
    public var end: TimeOfDay
}

public struct WeeklySchedule: Hashable, Sendable {
    public var weekday: [LaneWindow]
    public var weekend: [LaneWindow]

    /// The schedule WSDOT posted as of Nov 2026. Used when the page lists none.
    public static let builtIn = WeeklySchedule(
        weekday: [LaneWindow(status: .southbound, start: hm(5), end: hm(11)),
                  LaneWindow(status: .northbound, start: hm(11, 15), end: hm(23))],
        weekend: [LaneWindow(status: .southbound, start: hm(8), end: hm(13, 30)),
                  LaneWindow(status: .northbound, start: hm(13, 45), end: hm(23))]
    )
}

/// A stretch of time with one status. Published segments cover the horizon with no gaps.
public struct Segment: Hashable, Sendable {
    public var start: Moment
    public var end: Moment
    public var status: LaneStatus
}

public enum SourceKind: String, LenientEnum {
    case page, alert, holiday, models, other
    public static let fallback = SourceKind.other
}

/// A stretch of time the server can't vouch for, with the reason
public struct Doubt: Hashable, Sendable {
    public var start: Moment
    public var end: Moment
    public var title: String
    public var detail: String
    public var link: String?
    public var source: SourceKind
    /// True while a new page or alert is still being read, which usually clears up within minutes
    public var checking = false
}

public enum ChangeKind: String, LenientEnum {
    case northbound, southbound, closed, other, unclear
    case weekdaySchedule = "weekday_schedule"
    case weekendSchedule = "weekend_schedule"
    public static let fallback = ChangeKind.other
}

public enum Certainty: String, LenientEnum {
    case exact, approximate, unknown
    public static let fallback = Certainty.unknown
}

public enum NoticeSource: String, LenientEnum {
    case page, alert, other
    public static let fallback = NoticeSource.other
}

public struct Span: Hashable, Sendable {
    public var start: Moment?
    public var end: Moment?
}

/// One notice from the page or an alert, for the popover's lists
public struct Notice: Hashable, Sendable {
    public var title: String
    /// The page's own words
    public var detail: String
    public var link: String?
    public var kind: ChangeKind
    public var spans: [Span]
    public var startCertainty: Certainty
    public var endCertainty: Certainty
    public var source: NoticeSource
}

public enum DocumentStatus: String, LenientEnum {
    case answered, pending, failed, other
    public static let fallback = DocumentStatus.other
}

/// A page version or alert the server has read
public struct DocumentInfo: Hashable, Sendable {
    public var kind: String
    public var hash: String
    /// When the server first saw this version
    public var firstSeen: Moment
    /// Models whose answers were used, or "reviewed" for an answer a person wrote
    public var models: [String]
    public var status: DocumentStatus
    public var link: String?
}

public struct Horizon: Hashable, Sendable {
    public var start: Moment
    public var end: Moment
}

/// What the server worked out from WSDOT's page and alerts. Called Published in the TypeScript,
/// renamed here so it doesn't clash with Combine's @Published.
public struct Timeline: Hashable, Sendable {
    public var publishedAt: Moment
    /// Segments cover exactly this range
    public var horizon: Horizon
    /// The weekly schedule as the page lists it, or nil when it lists none
    public var schedule: WeeklySchedule?
    public var segments: [Segment]
    public var doubts: [Doubt]
    public var notices: [Notice]
    public var page: DocumentInfo?
    public var alerts: [DocumentInfo]
}

/// Minutes for one trip. Nil when WSDOT measured nothing.
public struct TripTimes: Hashable, Sendable {
    /// Through the express lanes. Nil while they're closed or run the other way.
    public var express: Int?
    /// On the regular lanes
    public var regular: Int?
    /// What the regular lanes usually take at this time of day
    public var usual: Int?
}

public struct Trips: Hashable, Sendable {
    public var northbound: TripTimes
    public var southbound: TripTimes
}

/// WSDOT's travel times through the express lanes, which only exist in the direction they're open
public struct LiveReading: Hashable, Sendable {
    /// When WSDOT measured it
    public var at: Moment
    /// Minutes from Seattle to Everett through the express lanes, or nil when there's no measurement
    public var northbound: Int?
    public var southbound: Int?
    /// Downtown Seattle to Everett and back, express lanes against the regular lanes. Missing in old readings.
    public var trips: Trips?
}

/// A WSDOT traffic camera along the express lanes
public struct Camera: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Where it is, like "Roanoke St Express Lanes"
    public var name: String
    public var milepost: Double
    /// WSDOT's name for it says it looks at the express lanes
    public var express: Bool
    public var lat: Double
    public var lon: Double
    /// A JPEG on WSDOT's server, updated about every 5 minutes
    public var image: String
}

/// GET /status
public struct ServerStatus: Hashable, Sendable {
    public var published: Timeline?
    /// When the server last read WSDOT's page successfully
    public var fetchedAt: Moment?
    /// When the server last tried
    public var checkedAt: Moment?
    /// Why the last try failed
    public var error: String?
    public var live: LiveReading?
    /// Cameras along the express lanes, south to north. Empty from older servers.
    public var cameras: [Camera] = []

    public static let empty = ServerStatus()
}

public enum Sources {
    public static let expressLanes = "https://wsdot.wa.gov/travel/roads-bridges/express-lanes"
    public static let alerts = "https://wsdot.com/travel/real-time/alerts"
    /// The travel map on the express lanes, with cameras, traffic and alerts on
    public static let travelMap =
        "https://wsdot.com/Travel/Real-time/Map/?layers=traffic-flow%2Calert%2Ccamera&base=wsdot&extent=-122.40%2C47.595%2C-122.25%2C47.715&fromLink=true"
    /// WSDOT Traffic on Bluesky, for King and Snohomish counties. Readable without signing in, unlike X.
    public static let wsdotTraffic = "https://bsky.app/profile/traffic.wsdot.wa.gov"
    /// The I-5 server this app reads
    public static let status = "https://i5.andrewmacheret.com/status"
}

// MARK: Decoding

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Swallows one array element that couldn't be read, so the rest still can
private struct Skip: Decodable {
    init(from decoder: Decoder) throws {}
}

private extension KeyedDecodingContainer where Key == AnyKey {
    /// A whole number, also accepting 18.0 or 18.4
    func number(_ key: String) throws -> Int {
        let k = AnyKey(key)
        if let i = try? decode(Int.self, forKey: k) { return i }
        return Int(try decode(Double.self, forKey: k).rounded())
    }

    /// Nil when missing or null
    func number(ifPresent key: String) throws -> Int? {
        let k = AnyKey(key)
        guard contains(k), try !decodeNil(forKey: k) else { return nil }
        return try number(key)
    }

    func value<T: Decodable>(_ key: String, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: AnyKey(key)) ?? value
    }

    func optional<T: Decodable>(_ key: String) throws -> T? {
        try decodeIfPresent(T.self, forKey: AnyKey(key))
    }

    func required<T: Decodable>(_ key: String) throws -> T {
        try decode(T.self, forKey: AnyKey(key))
    }

    /// The elements that could be read, dropping the rest
    func lossy<T: Decodable>(_ key: String) -> [T] {
        guard var list = try? nestedUnkeyedContainer(forKey: AnyKey(key)) else { return [] }
        var out: [T] = []
        while !list.isAtEnd {
            if let item = try? list.decode(T.self) {
                out.append(item)
            } else if (try? list.decode(Skip.self)) == nil {
                break
            }
        }
        return out
    }
}

private func keyed(_ decoder: Decoder) throws -> KeyedDecodingContainer<AnyKey> {
    try decoder.container(keyedBy: AnyKey.self)
}

extension LaneWindow: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(status: try c.value("status", default: .unknown), start: try c.number("start"), end: try c.number("end"))
    }
}

extension WeeklySchedule: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(weekday: try c.value("weekday", default: []), weekend: try c.value("weekend", default: []))
    }
}

extension Segment: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(start: try c.number("start"), end: try c.number("end"), status: try c.value("status", default: .unknown))
    }
}

extension Doubt: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(start: try c.number("start"), end: try c.number("end"),
                  title: try c.value("title", default: ""), detail: try c.value("detail", default: ""),
                  link: try c.optional("link"), source: try c.value("source", default: .other),
                  checking: try c.value("checking", default: false))
    }
}

extension Span: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(start: try c.number(ifPresent: "start"), end: try c.number(ifPresent: "end"))
    }
}

extension Notice: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(title: try c.value("title", default: ""), detail: try c.value("detail", default: ""),
                  link: try c.optional("link"), kind: try c.value("kind", default: .other),
                  spans: try c.value("spans", default: []),
                  startCertainty: try c.value("startCertainty", default: .unknown),
                  endCertainty: try c.value("endCertainty", default: .unknown),
                  source: try c.value("source", default: .other))
    }
}

extension DocumentInfo: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(kind: try c.value("kind", default: ""), hash: try c.value("hash", default: ""),
                  firstSeen: try c.number(ifPresent: "firstSeen") ?? 0, models: try c.value("models", default: []),
                  status: try c.value("status", default: .other), link: try c.optional("link"))
    }
}

extension Horizon: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(start: try c.number("start"), end: try c.number("end"))
    }
}

extension Timeline: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(publishedAt: try c.number(ifPresent: "publishedAt") ?? 0, horizon: try c.required("horizon"),
                  schedule: try c.optional("schedule"), segments: try c.value("segments", default: []),
                  doubts: try c.value("doubts", default: []), notices: c.lossy("notices"),
                  page: try c.optional("page"), alerts: c.lossy("alerts"))
    }
}

extension TripTimes: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(express: try c.number(ifPresent: "express"), regular: try c.number(ifPresent: "regular"),
                  usual: try c.number(ifPresent: "usual"))
    }
}

extension Trips: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        let none = TripTimes(express: nil, regular: nil, usual: nil)
        self.init(northbound: try c.value("northbound", default: none), southbound: try c.value("southbound", default: none))
    }
}

extension LiveReading: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(at: try c.number("at"), northbound: try c.number(ifPresent: "northbound"),
                  southbound: try c.number(ifPresent: "southbound"), trips: try? c.optional("trips"))
    }
}

extension Camera: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(id: try c.number("id"), name: try c.value("name", default: ""),
                  milepost: try c.value("milepost", default: 0), express: try c.value("express", default: false),
                  lat: try c.required("lat"), lon: try c.required("lon"), image: try c.required("image"))
    }
}

extension ServerStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        self.init(published: try c.optional("published"), fetchedAt: try c.number(ifPresent: "fetchedAt"),
                  checkedAt: try c.number(ifPresent: "checkedAt"), error: try c.optional("error"),
                  live: try? c.optional("live"), cameras: c.lossy("cameras"))
    }
}
