import Foundation

/// What each popover section says, taken from the web page (i5-client's Page.tsx).
/// The views only lay this out, so tests can check the words without drawing anything.
public enum Page {
    /// "Planned changes" lists notices with a time starting within this many days
    public static let plannedDays = 14
    /// Times listed per notice before the rest fold behind "…"
    public static let maxTimes = 20
    private static let dayMs = 24 * 60 * 60_000

    // MARK: Status

    public enum Tone: Sendable { case northbound, southbound, closed, unknown, warning }

    public struct Header: Hashable, Sendable {
        public var title: String
        public var subtitle: String
        public var tone: Tone
    }

    /// `loading` means nothing has come from the server yet, not even a saved copy
    public static func header(_ snap: Snapshot, loading: Bool, loadError: String? = nil) -> Header {
        let check = snap.check
        if loading {
            if loadError != nil { return Header(title: "Can't reach the server", subtitle: "The app keeps trying", tone: .warning) }
            return Header(title: "Loading…", subtitle: "Asking the server", tone: .unknown)
        }
        switch check.verdict {
        case .confident:
            let subtitle: String
            if let next = snap.next {
                subtitle = next.to == .unknown
                    ? "No changes before \(Format.shortDate(next.at))"
                    : "\(Snapshot.verb(check.scheduled, next.to)) at \(Format.when(next.at, now: snap.now)) · \(Format.countdown(to: next.at, from: snap.now))"
            } else {
                subtitle = "No changes coming up"
            }
            return Header(title: check.scheduled.title, subtitle: subtitle, tone: tone(check.scheduled))
        case .checking:
            // The app's own download in progress says "Asking the server"
            let reading = check.concerns.contains { $0.checking }
            return Header(title: "Checking…", subtitle: reading ? "Reading WSDOT's latest update" : "Asking the server", tone: .unknown)
        case .uncertain:
            let subtitle = check.scheduled == .unknown
                ? "Don't rely on the app right now"
                : "Expected \(check.scheduled.title.lowercased()), but don't rely on it"
            return Header(title: "Can't confirm", subtitle: subtitle, tone: .warning)
        }
    }

    private static func tone(_ s: LaneStatus) -> Tone {
        switch s {
        case .northbound: .northbound
        case .southbound: .southbound
        case .closed: .closed
        case .unknown: .unknown
        }
    }

    public static let liveSourcesLead = "Check a live source before you drive:"

    public enum CamerasLink: Hashable, Sendable {
        /// Open the Cameras section and scroll to it
        case section
        case url(String)
    }

    /// Where "Traffic cameras" goes: the Cameras section when the server sent cameras, otherwise the travel map
    public static func trafficCameras(_ status: ServerStatus) -> CamerasLink {
        status.cameras.isEmpty ? .url(Sources.travelMap) : .section
    }

    // MARK: Notices

    public enum NoticeTone: Sendable { case bad, warn, muted }

    public static func tone(_ kind: ChangeKind) -> NoticeTone {
        switch kind {
        case .closed: .bad
        case .other: .muted
        default: .warn
        }
    }

    public struct TodayNotice: Hashable, Sendable {
        public var notice: Notice
        public var start: Moment
        public var end: Moment?
        /// "Now until 11:00 AM Mon. It could last longer."
        public var text: String
    }

    /// Notices in effect now or starting later today
    public static func noticesToday(_ snap: Snapshot) -> [TodayNotice] {
        let endOfToday = Seattle.startOfDay(Seattle.addDays(snap.today, 1))
        return (snap.status.published?.notices ?? []).compactMap { n in
            guard let span = n.spans.first(where: { s in
                guard let start = s.start else { return false }
                return start < endOfToday && (s.end.map { $0 > snap.now } ?? true)
            }), let start = span.start else { return nil }
            let until = span.end.map { "until \(Format.when($0, now: snap.now))" } ?? "with no end given"
            var text = start <= snap.now ? "Now \(until)." : "From \(Format.clock(start)) \(until)."
            if n.endCertainty != .exact, span.end != nil { text += " It could last longer." }
            return TodayNotice(notice: n, start: start, end: span.end, text: text)
        }
    }

    // MARK: Timelines

    public static func timelineTitle(_ snap: Snapshot) -> String {
        snap.check.verdict == .confident ? "Schedule" : "Expected schedule · not confirmed"
    }

    /// "Southbound 5 AM to 11 AM, Northbound 11:15 AM to 11 PM", for VoiceOver
    public static func timelineSummary(_ segments: [DaySegment]) -> String {
        let open = segments.filter { $0.status != .closed }
        if open.isEmpty { return "Closed all day" }
        return open.map { "\($0.status.title) \(timeLabel($0.start)) to \(timeLabel($0.end))" }.joined(separator: ", ")
    }

    /// The first doubt between now and the end of today, for the warning next to "Today"
    public static func todayDoubt(_ snap: Snapshot) -> Doubt? {
        let endOfToday = Seattle.startOfDay(Seattle.addDays(snap.today, 1))
        return snap.status.published?.doubts(from: snap.now, to: endOfToday).first
    }

    // MARK: Travel times

    public struct TravelRow: Hashable, Sendable {
        public var label: String
        public var times: TripTimes
        /// "18 min" or "—"
        public var express: String
        public var regular: String
        /// Minutes the express lanes save, only when it's 2 or more
        public var saves: Int?
    }

    public struct TravelTimes: Hashable, Sendable {
        public var rows: [TravelRow]
        public var hint: String
    }

    /// Express lanes against the regular lanes, from WSDOT's sensors. Nil when there's nothing recent to show.
    public static func travelTimes(_ snap: Snapshot) -> TravelTimes? {
        guard let live = snap.status.live, let trips = live.trips, snap.now - live.at <= Trust.liveMaxAge else { return nil }
        let pairs = [("Seattle → Everett", trips.northbound), ("Everett → Seattle", trips.southbound)]
        if pairs.allSatisfy({ $0.1.express == nil && $0.1.regular == nil }) { return nil }
        let min = { (m: Int?) in m.map { "\($0) min" } ?? "—" }
        let rows = pairs.map { label, t in
            let saves = t.express.flatMap { e in t.regular.map { $0 - e } } ?? 0
            return TravelRow(label: label, times: t, express: min(t.express), regular: min(t.regular), saves: saves >= 2 ? saves : nil)
        }
        var hint = "Downtown Seattle to Everett, from WSDOT's sensors at \(Format.clock(live.at))."
        if rows.contains(where: { $0.times.express == nil }) { hint += " A dash means the express lanes aren't open that way." }
        return TravelTimes(rows: rows, hint: hint)
    }

    // MARK: Coming up

    public static func comingUp(_ snap: Snapshot) -> [Change] { snap.changes.filter { $0.to != .unknown } }

    public static func doubtful(_ snap: Snapshot, _ at: Moment) -> Bool { snap.doubtfulDays.contains(Seattle.day(at)) }

    // MARK: Planned changes

    public struct PlannedNotice: Hashable, Sendable {
        public var notice: Notice
        /// Every time still to come, as text
        public var times: [String]
        /// The first `maxTimes` show, the rest fold behind "…"
        public var shownTimes: [String] { Array(times.prefix(maxTimes)) }
        public var moreTimes: [String] { Array(times.dropFirst(maxTimes)) }
        /// "Show 5 more times", for the "…"
        public var moreLabel: String? { moreTimes.isEmpty ? nil : "Show \(moreTimes.count) more times" }
        /// Approximate or open-ended times, in orange
        public var note: String?
        /// "WSDOT's words" or "WSDOT's alert", which opens the notice's own text
        public var wordsTitle: String
        /// Set when the notice links somewhere other than the express lanes page
        public var moreInfo: String?
    }

    public struct Planned: Hashable, Sendable {
        public var notices: [PlannedNotice]
        /// Holidays with no notice
        public var holidays: [Doubt]
    }

    /// Notices with times in the next two weeks, and holidays with no notice
    public static func planned(_ snap: Snapshot) -> Planned? {
        guard let p = snap.status.published else { return nil }
        let until = snap.now + plannedDays * dayMs
        let notices: [PlannedNotice] = p.notices.compactMap { n in
            let spans = n.spans.filter { s in s.end.map { $0 > snap.now } ?? true }
            guard spans.contains(where: { s in s.start.map { $0 < until } ?? true }) else { return nil }
            let link = n.link.flatMap { $0 != Sources.expressLanes ? $0 : nil }
            return PlannedNotice(notice: n, times: spans.map(spanText), note: certaintyText(n),
                                 wordsTitle: n.source == .alert ? "WSDOT's alert" : "WSDOT's words", moreInfo: link)
        }
        let holidays = p.doubts.filter { $0.source == .holiday && $0.end > snap.now && $0.start < until }
        if notices.isEmpty, holidays.isEmpty { return nil }
        return Planned(notices: notices, holidays: holidays)
    }

    /// "Wed, Dec 2 9:00 PM → Thu, Dec 3 5:00 AM"
    public static func spanText(_ s: Span) -> String {
        guard let startMs = s.start else { return "No dates given" }
        let start = "\(Format.shortDate(startMs)) \(Format.clock(startMs))"
        guard let end = s.end else { return "From \(start), no end given" }
        let sameDay = Seattle.day(end) == Seattle.day(startMs)
        return "\(start) → \(sameDay ? "" : "\(Format.shortDate(end)) ")\(Format.clock(end))"
    }

    public static func certaintyText(_ n: Notice) -> String? {
        if n.kind == .unclear { return "Exact times unclear. The app won't confirm a direction then." }
        var parts: [String] = []
        if n.startCertainty == .approximate { parts.append("Start time is approximate.") }
        if n.endCertainty == .approximate { parts.append("End time is approximate.") }
        if n.endCertainty == .unknown, n.spans.contains(where: { $0.end != nil }) { parts.append("It could last longer.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Regular schedule

    public static func regularSchedule(_ snap: Snapshot) -> (schedule: WeeklySchedule, hint: String?) {
        let listed = snap.status.published?.schedule
        let hint = snap.status.published != nil && listed == nil
            ? "WSDOT's page doesn't list its regular schedule right now. These are the hours it listed in Nov. 2026."
            : nil
        return (listed ?? .builtIn, hint)
    }

    // MARK: Sources

    public struct SourceLink: Hashable, Sendable {
        public var title: String
        public var subtitle: String
        public var url: String
    }

    public static func sources(_ snap: Snapshot) -> [SourceLink] {
        let p = snap.status.published
        var seen: Set<String> = [Sources.expressLanes]
        var out = [SourceLink(title: "WSDOT express lanes schedule", subtitle: "Where this data comes from", url: Sources.expressLanes)]
        for n in p?.notices ?? [] where n.source == .page {
            guard let l = n.link, seen.insert(l).inserted else { continue }
            out.append(SourceLink(title: "Linked from WSDOT's page", subtitle: URL(string: l)?.host() ?? l, url: l))
        }
        for a in p?.alerts ?? [] {
            guard let l = a.link else { continue }
            out.append(SourceLink(title: "WSDOT highway alert", subtitle: "About the express lanes", url: l))
        }
        out.append(SourceLink(title: "WSDOT real-time travel map", subtitle: "Live traffic, alerts and cameras", url: Sources.travelMap))
        out.append(SourceLink(title: "WSDOT Traffic on Bluesky", subtitle: "Unplanned closures get posted here first", url: Sources.wsdotTraffic))
        return out
    }

    public static let sourcesHint = """
    WSDOT doesn't publish a live feed for the express lanes. The server reads WSDOT's page and highway alerts every \
    15 minutes, two AI models read each new notice, and code checks their answers and works out the times. The app \
    only shows a direction when the server read WSDOT recently, both models agree, nothing about now is unclear, and \
    WSDOT's travel time sensors don't show traffic going the other way. Otherwise it shows ⚠. It can't know about \
    closures WSDOT hasn't posted yet.
    """

    // MARK: Data status

    /// "Checked WSDOT at 3:00 PM", and whether it's a warning
    public static func dataStatus(_ snap: Snapshot, loaded: Bool) -> (text: String, warn: Bool) {
        let s = snap.status
        if !loaded { return ("Loading…", false) }
        if let fetchedAt = s.fetchedAt, s.error == nil { return ("Checked WSDOT at \(Format.when(fetchedAt, now: snap.now))", false) }
        if let fetchedAt = s.fetchedAt {
            return ("WSDOT didn't answer at \(Format.clock(s.checkedAt ?? snap.now)). Using what it said at \(Format.when(fetchedAt, now: snap.now)).", true)
        }
        return (s.published != nil ? "The server hasn't read WSDOT's page yet." : "The server hasn't published a schedule yet.", true)
    }

    /// Which models read the notices
    public static func readingText(_ snap: Snapshot) -> String? {
        guard let page = snap.status.published?.page else { return nil }
        switch page.status {
        case .pending: return "Reading WSDOT's latest update…"
        case .failed: return "Couldn't read WSDOT's latest update, so earlier notices are shown."
        default:
            if page.models.contains("reviewed") { return "Notices checked by hand." }
            return "Notices read by \(page.models.joined(separator: " and "))."
        }
    }

    /// What WSDOT's sensors measured through the express lanes
    public static func liveText(_ snap: Snapshot) -> String? {
        guard let live = snap.status.live, snap.now - live.at <= 30 * 60_000 else { return nil }
        let parts = [
            live.northbound.flatMap { $0 != 0 ? "\($0) min northbound" : nil },
            live.southbound.flatMap { $0 != 0 ? "\($0) min southbound" : nil },
        ].compactMap { $0 }
        let what = parts.isEmpty ? "no traffic" : parts.joined(separator: ", ")
        return "WSDOT's sensors at \(Format.clock(live.at)): \(what) through the express lanes."
    }
}
