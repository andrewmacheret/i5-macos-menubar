import Foundation

/// A reason the app can't vouch for what it shows.
public struct Concern: Hashable, Sendable {
    public var title: String
    public var detail: String
    public var link: String?
    /// True while the server is still reading a new page or alert, which usually clears up in minutes
    public var checking: Bool
    /// True for "data is old" problems that the app's own download in progress may fix.
    /// The web page has no such idea. The app uses it to show ? instead of ⚠ while it refreshes.
    public var fixedByRefresh: Bool

    public init(_ title: String, _ detail: String, link: String? = nil, checking: Bool = false, fixedByRefresh: Bool = false) {
        self.title = title
        self.detail = detail
        self.link = link
        self.checking = checking
        self.fixedByRefresh = fixedByRefresh
    }
}

public struct Assessment: Hashable, Sendable {
    public enum Verdict: String, Sendable { case confident, checking, uncertain }

    public var verdict: Verdict
    /// What the published timeline says right now, trusted or not
    public var scheduled: LaneStatus
    public var concerns: [Concern]

    /// What the badge should show. Never a direction unless confident.
    public var shown: LaneStatus? { verdict == .confident ? scheduled : nil }
}

/// Decides when the app is allowed to show a confident N or S.
/// The rule is simple: if anything looks off, say so instead of guessing.
public enum Trust {
    /// The server reads WSDOT every 15 minutes, so data older than this means it's stuck
    public static let maxAge = 2 * 60 * 60_000
    /// Sensor readings older than this are ignored
    public static let liveMaxAge = 30 * 60_000
    /// WSDOT's travel times lag a switch by up to this long, so readings this soon after one are ignored
    public static let liveLag = 30 * 60_000
    static let clockSlack = 5 * 60_000

    /// `refreshing` means the app is downloading right now, so old data shows as "checking"
    /// for a moment instead of a warning. Without it this matches the web page exactly.
    public static func assess(_ status: ServerStatus, now: Moment, refreshing: Bool = false) -> Assessment {
        let p = status.published
        let scheduled = p?.status(at: now) ?? .unknown
        let concerns = dataConcerns(status, now: now) + (p.map { momentConcerns($0, now: now) } ?? []) + liveConcerns(status, now: now)
        let verdict: Assessment.Verdict
        if concerns.isEmpty, scheduled != .unknown {
            verdict = .confident
        } else if !concerns.isEmpty, concerns.allSatisfy({ $0.checking || (refreshing && $0.fixedByRefresh) }) {
            verdict = .checking
        } else {
            verdict = .uncertain
        }
        return Assessment(verdict: verdict, scheduled: scheduled, concerns: concerns)
    }

    /// Problems with the data as a whole
    public static func dataConcerns(_ status: ServerStatus, now: Moment) -> [Concern] {
        guard let published = status.published else {
            return [Concern("Can't reach the server", "The server hasn't published anything yet.",
                            link: Sources.expressLanes, fixedByRefresh: true)]
        }
        var out: [Concern] = []
        if status.fetchedAt == nil || now - status.fetchedAt! > maxAge {
            let at = status.fetchedAt ?? published.publishedAt
            let error = status.error.map { " \($0)." } ?? ""
            out.append(Concern("Data is \(Format.countdown(to: now, from: at)) old",
                               "The server last read WSDOT's page at \(Format.when(at, now: now)).\(error)",
                               link: Sources.expressLanes, fixedByRefresh: true))
        } else if let fetchedAt = status.fetchedAt, fetchedAt - now > clockSlack {
            out.append(Concern("This device's clock is off",
                               "WSDOT's page was read at a time that hasn't happened yet on this device. Check the clock in your settings.",
                               link: Sources.expressLanes))
        }
        if now >= published.horizon.end || now < published.horizon.start {
            out.append(Concern("No schedule for today", "The server's timeline doesn't cover today.",
                               link: Sources.expressLanes, fixedByRefresh: true))
        }
        return out
    }

    /// The server's doubts about this moment
    public static func momentConcerns(_ p: Timeline, now: Moment) -> [Concern] {
        p.doubts(at: now).map { Concern($0.title, $0.detail, link: $0.link ?? Sources.expressLanes, checking: $0.checking) }
    }

    public enum LiveSeen: String, Sendable { case northbound, southbound, none, both }

    /// What WSDOT's sensors see, compared with the timeline
    public static func liveReadingStatus(_ r: LiveReading) -> LiveSeen {
        let n = (r.northbound ?? 0) > 0
        let s = (r.southbound ?? 0) > 0
        return n && s ? .both : n ? .northbound : s ? .southbound : .none
    }

    public static func liveConcerns(_ status: ServerStatus, now: Moment) -> [Concern] {
        guard let live = status.live, let published = status.published,
              now - live.at <= liveMaxAge, live.at - now <= clockSlack else { return [] }
        let expected = published.status(at: live.at)
        if expected == .unknown { return [] }
        // Right after a switch the sensors still show the old direction
        if let changed = published.lastChange(at: live.at), live.at - changed < liveLag { return [] }
        let should = expected.title.lowercased()
        switch liveReadingStatus(live) {
        case .both:
            return []
        case .none:
            guard expected.isOpen else { return [] }
            return [Concern("No traffic measured",
                            "The lanes should be \(should), but WSDOT's sensors measured no traffic through them at \(Format.clock(live.at)).",
                            link: Sources.travelMap)]
        case let seen:
            if seen.rawValue == expected.rawValue { return [] }
            return [Concern("WSDOT's sensors show \(seen.rawValue) traffic",
                            "The lanes should be \(should), but WSDOT's sensors measured \(seen.rawValue) traffic at \(Format.clock(live.at)).",
                            link: Sources.travelMap)]
        }
    }
}
