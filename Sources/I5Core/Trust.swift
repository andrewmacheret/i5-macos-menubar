import Foundation

/// A reason the app can't vouch for what it shows.
public struct Concern: Hashable, Sendable {
    public var title: String
    public var detail: String
    public var link: URL?
    /// True for "data is old" problems that a refresh in progress may fix
    public var fixedByRefresh: Bool

    public init(_ title: String, _ detail: String, link: URL? = nil, fixedByRefresh: Bool = false) {
        self.title = title
        self.detail = detail
        self.link = link
        self.fixedByRefresh = fixedByRefresh
    }
}

public struct Assessment: Sendable {
    public enum Verdict: Sendable { case confident, checking, uncertain }

    public var verdict: Verdict
    /// What the posted schedule says right now, trusted or not
    public var scheduled: LaneStatus
    public var concerns: [Concern]

    /// What the icon should show. Never a direction unless confident.
    public var shown: LaneStatus? {
        verdict == .confident ? scheduled : nil
    }
}

/// Decides when the app is allowed to show a confident N or S.
/// The rule is simple: if anything looks off, say so instead of guessing.
public enum Trust {
    /// Data older than this is treated as stale
    public static let maxAge: TimeInterval = 2 * 60 * 60

    /// `refreshing` means a download is in flight, so old data shows as "checking"
    /// for a moment instead of a warning.
    public static func assess(_ result: FetchResult, now: Date, refreshing: Bool = false) -> Assessment {
        let engine = Engine(info: result.info)
        let today = Seattle.day(of: now)
        let concerns = dataConcerns(result, now: now) + dayConcerns(result.info, day: today, today: today)
        let verdict: Assessment.Verdict
        if concerns.isEmpty {
            verdict = .confident
        } else if refreshing, concerns.allSatisfy(\.fixedByRefresh) {
            verdict = .checking
        } else {
            verdict = .uncertain
        }
        return Assessment(verdict: verdict, scheduled: engine.status(at: now), concerns: concerns)
    }

    /// Problems with the data as a whole.
    public static func dataConcerns(_ result: FetchResult, now: Date) -> [Concern] {
        var out: [Concern] = []
        let info = result.info

        switch result.source {
        case .builtIn:
            out.append(Concern("Can't reach WSDOT", "Only the schedule built into the app is available, and it may be out of date.",
                               link: Sources.expressLanes, fixedByRefresh: !result.pageChanged))
        case .cached(let d), .live(let d):
            if now.timeIntervalSince(d) > maxAge {
                out.append(Concern("Data is \(Format.countdown(to: now, from: d)) old",
                                   "Last read WSDOT's page at \(Format.when(d, now: now)). The app keeps retrying.",
                                   link: Sources.expressLanes, fixedByRefresh: true))
            }
        }

        if result.pageChanged {
            out.append(Concern("WSDOT's page changed", "The app couldn't read the new page, so it's using an older saved copy.", link: Sources.expressLanes))
        }
        for w in info.warnings {
            out.append(Concern("Part of WSDOT's page couldn't be read", w, link: Sources.expressLanes))
        }
        if let problem = scheduleProblem(info.schedule) {
            out.append(Concern("Schedule looks wrong", problem, link: Sources.expressLanes))
        }
        return out
    }

    /// Things that might make one day differ from the regular schedule.
    public static func dayConcerns(_ info: ExpressLanesInfo, day: DayKey, today: DayKey) -> [Concern] {
        var out: [Concern] = []

        if let holiday = Holidays.name(for: day) {
            out.append(Concern("\(holiday) may run a holiday schedule",
                               "WSDOT doesn't post holiday schedules on its express lanes page."))
        }
        for a in info.advisories where applies(a.days, to: day, today: today) {
            out.append(Concern("WSDOT posted a notice", a.text, link: a.link ?? Sources.expressLanes))
        }
        for e in info.events where e.closure == nil && applies(e.days, to: day, today: today) {
            out.append(Concern(e.title, e.detail.isEmpty ? "The app couldn't tell exactly when this happens." : e.detail,
                               link: e.link ?? Sources.expressLanes))
        }
        if let early = info.earlyClose(on: day), early.time == nil {
            out.append(Concern("Closing early, time unknown", "WSDOT lists this as an early closure day but the app couldn't read the time.",
                               link: Sources.expressLanes))
        }
        return out
    }

    /// Undated notices count for today only, since they're on the page right now.
    private static func applies(_ days: DayRange?, to day: DayKey, today: DayKey) -> Bool {
        guard let days else { return day == today }
        return days.contains(day)
    }

    static func scheduleProblem(_ s: WeeklySchedule) -> String? {
        for (name, list) in [("weekday", s.weekday), ("weekend", s.weekend)] {
            if list.isEmpty { return "No \(name) hours found." }
            let sorted = list.sorted { $0.start < $1.start }
            for (i, w) in sorted.enumerated() {
                if w.start >= w.end { return "A \(name) time range ends before it starts." }
                if i > 0, sorted[i - 1].end > w.start { return "Two \(name) time ranges overlap." }
                if w.status == .closed || w.status == .unknown { return "A \(name) time range has no direction." }
            }
        }
        return nil
    }
}
