import Foundation

/// Reads the WSDOT express lanes page into an `ExpressLanesInfo`.
public enum Parser {
    public static func parse(html: String, now: Date = Date()) -> ExpressLanesInfo {
        var weekday: [LaneWindow] = []
        var weekend: [LaneWindow] = []
        var advisories: [Advisory] = []
        var earlyCloses: [EarlyClose] = []
        var earlyDefault: TimeOfDay?
        var events: [SpecialEvent] = []
        var warnings: [String] = []

        // Only read the express lanes part of the page, not the site nav and footer
        let all = HTML.blocks(in: html)
        guard let start = all.firstIndex(where: { $0.kind == .h2 && $0.text.lowercased().contains("express lanes schedule") }) else {
            return ExpressLanesInfo(warnings: ["Couldn't find the schedule section on WSDOT's page"])
        }
        let end = all[(start + 1)...].firstIndex { $0.kind == .h2 && $0.text.lowercased().contains("map") } ?? all.endIndex
        let blocks = all[start..<end]

        enum Section { case schedule, special, unknown }
        var section = Section.schedule
        var h3: String?
        var pendingEvent: SpecialEvent?

        func flushEvent() {
            guard var e = pendingEvent else { return }
            let text = e.title + " " + e.detail
            e.closure = closure(from: e, now: now)
            if let c = e.closure {
                e.days = DayRange(first: Seattle.day(of: c.start), last: Seattle.day(of: c.end))
            } else {
                e.days = range(in: text, now: now)
            }
            events.append(e)
            pendingEvent = nil
        }

        for b in blocks {
            let lower = b.text.lowercased()
            switch b.kind {
            case .h2:
                flushEvent()
                h3 = nil
                if lower.contains("express lanes schedule") {
                    section = .schedule
                } else if lower.contains("special") {
                    section = .special
                } else {
                    section = .unknown
                    warnings.append("New section on WSDOT's page: \(b.text)")
                }
            case .h3:
                flushEvent()
                h3 = lower
                if section == .schedule, !isWeekdayHeading(lower), !isWeekendHeading(lower) {
                    warnings.append("New schedule section on WSDOT's page: \(b.text)")
                }
                if section == .special, !lower.contains("closing early") {
                    pendingEvent = SpecialEvent(title: b.text, detail: "", link: nil)
                }
            case .p, .li:
                switch section {
                case .unknown:
                    continue
                case .schedule:
                    if b.kind == .p {
                        // Any note in the schedule area could change today's plan
                        advisories.append(Advisory(text: b.text, link: absolute(b.href), days: range(in: b.text, now: now)))
                        continue
                    }
                    if lower.hasPrefix("closed") { continue }
                    guard let h3, let w = window(from: b.text) else {
                        warnings.append("Couldn't read schedule line: \(b.text)")
                        continue
                    }
                    if isWeekendHeading(h3) { weekend.append(w) }
                    else if isWeekdayHeading(h3) { weekday.append(w) }
                case .special:
                    if h3?.contains("closing early") == true {
                        if b.kind == .p {
                            earlyDefault = Times.first(after: "close at", in: b.text) ?? earlyDefault
                        } else {
                            let days = Dates.all(in: b.text, near: now)
                            if days.isEmpty { warnings.append("Couldn't read early closure date: \(b.text)") }
                            // A date can carry its own time, like "Monday, Nov. 30 at 8 p.m."
                            let own = Times.explicit(in: b.text)
                            earlyCloses += days.map { EarlyClose(day: $0, time: own ?? earlyDefault) }
                        }
                    } else if pendingEvent != nil {
                        let sep = pendingEvent!.detail.isEmpty ? "" : "\n"
                        pendingEvent!.detail += sep + b.text
                        if pendingEvent!.link == nil { pendingEvent!.link = absolute(b.href) }
                    } else {
                        advisories.append(Advisory(text: b.text, link: absolute(b.href), days: range(in: b.text, now: now)))
                    }
                }
            }
        }
        flushEvent()

        let fromPage = !weekday.isEmpty && !weekend.isEmpty
        if !fromPage { warnings.append("Couldn't read the weekday and weekend schedule on WSDOT's page") }
        return ExpressLanesInfo(
            schedule: fromPage ? WeeklySchedule(weekday: weekday, weekend: weekend) : .builtIn,
            scheduleFromPage: fromPage,
            earlyCloses: earlyCloses.sorted { $0.day < $1.day },
            events: events,
            advisories: advisories,
            warnings: warnings
        )
    }

    private static func isWeekdayHeading(_ s: String) -> Bool {
        (s.contains("monday") && s.contains("friday")) || s.contains("weekday")
    }

    private static func isWeekendHeading(_ s: String) -> Bool {
        (s.contains("saturday") && s.contains("sunday")) || s.contains("weekend")
    }

    /// The span of dates a notice talks about. Open ended if it says "until further notice".
    static func range(in text: String, now: Date) -> DayRange? {
        let days = Dates.all(in: text, near: now)
        guard let first = days.min(), let last = days.max() else { return nil }
        let openEnded = text.range(of: #"further notice|indefinite|until repairs|until it is safe"#, options: [.regularExpression, .caseInsensitive]) != nil
        return DayRange(first: first, last: openEnded ? nil : last)
    }

    /// "Southbound - 5 a.m. to 11 a.m." or "Northbound - 1:45 to 11 p.m."
    static func window(from text: String) -> LaneWindow? {
        let lower = text.lowercased()
        let status: LaneStatus
        if lower.hasPrefix("southbound") { status = .southbound }
        else if lower.hasPrefix("northbound") { status = .northbound }
        else { return nil }

        if lower.contains("24 hours") { return LaneWindow(status, .midnight, .endOfDay) }

        let rest = lower.drop { $0 != "-" && $0 != "–" && $0 != "—" && $0 != ":" }.dropFirst()
        let parts = String(rest).components(separatedBy: " to ")
        guard parts.count >= 2, let end = Times.parse(parts[1]) else { return nil }

        // Times like "1:45 to 11 p.m." borrow the am/pm from the end time
        guard var start = Times.parse(parts[0], defaultPM: end.pm) else { return nil }
        if start.time >= end.time, end.pm, !start.explicit {
            start = Times.parse(parts[0], defaultPM: false) ?? start
        }
        let endTime = end.time == .midnight ? TimeOfDay.endOfDay : end.time
        return LaneWindow(status, start.time, endTime)
    }

    /// Finds "11 p.m. Friday, Dec. 4 to 4 a.m. Monday, Dec. 7" style ranges.
    static func closure(from event: SpecialEvent, now: Date) -> Closure? {
        // Only trust headings that say closure, so lane reductions don't count
        guard event.title.lowercased().contains("clos") else { return nil }

        let time = #"(\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?|noon|midnight)"#
        let day = #"(?:[A-Za-z]+day,?\s+)?"#
        let date = #"([A-Za-z]{3,9}\.?\s+\d{1,2})"#
        let sep = #"\s+(?:to|through|until|-|–)\s+"#
        // "11 p.m. Friday, Dec. 4 to 4 a.m. Monday, Dec. 7"
        let timeFirst = time + #"\s+"# + day + date + sep + time + #"\s+"# + day + date
        // "Friday, Dec. 4 at 11 p.m. to Monday, Dec. 7 at 4 a.m."
        let dateFirst = day + date + #",?\s+at\s+"# + time + sep + day + date + #",?\s+at\s+"# + time

        if let g = Regex.groups(timeFirst, in: event.detail) {
            return make(event.title, g[1], g[0], g[3], g[2], now)
        }
        if let g = Regex.groups(dateFirst, in: event.detail) {
            return make(event.title, g[0], g[1], g[2], g[3], now)
        }
        // No exact times. Don't guess, Trust flags those days instead.
        return nil
    }

    private static func make(_ title: String, _ d1: String, _ t1: String, _ d2: String, _ t2: String, _ now: Date) -> Closure? {
        guard let day1 = Dates.all(in: d1, near: now).first,
              var day2 = Dates.all(in: d2, near: now).first,
              let time1 = Times.parse(t1)?.time,
              let time2 = Times.parse(t2)?.time
        else { return nil }
        if day2 < day1 { day2.year += 1 }
        guard let s = Seattle.date(day1, time1), let e = Seattle.date(day2, time2) else { return nil }
        return Closure(title: title, start: s, end: e)
    }

    static func absolute(_ href: String?) -> URL? {
        guard let href else { return nil }
        if href.hasPrefix("http") { return URL(string: href) }
        if href.hasPrefix("/") { return URL(string: "https://wsdot.wa.gov" + href) }
        return nil
    }
}

enum Regex {
    static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}

enum Times {
    struct Parsed {
        var time: TimeOfDay
        var pm: Bool
        /// False when am/pm was guessed
        var explicit: Bool
    }

    static func parse(_ text: String, defaultPM: Bool? = nil) -> Parsed? {
        let lower = text.lowercased()
        if lower.contains("noon") { return Parsed(time: TimeOfDay(12), pm: true, explicit: true) }
        if lower.contains("midnight") { return Parsed(time: .midnight, pm: false, explicit: true) }

        guard let g = Regex.groups(#"(\d{1,2})(?::(\d{2}))?\s*(a\.?\s?m\.?|p\.?\s?m\.?)?"#, in: lower),
              var hour = Int(g[0]), hour <= 12
        else { return nil }
        let minute = Int(g[1]) ?? 0
        let marker = g[2]
        let explicit = !marker.isEmpty
        let pm = explicit ? marker.hasPrefix("p") : (defaultPM ?? false)
        if hour == 12 { hour = 0 }
        if pm { hour += 12 }
        return Parsed(time: TimeOfDay(hour, minute), pm: pm, explicit: explicit)
    }

    /// Only times that say a.m., p.m., noon or midnight, so "Nov. 30" isn't read as 30 o'clock
    static func explicit(in text: String) -> TimeOfDay? {
        guard let g = Regex.groups(#"(\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?|\bnoon\b|\bmidnight\b)"#, in: text) else { return nil }
        return parse(g[0])?.time
    }

    static func first(after phrase: String, in text: String) -> TimeOfDay? {
        guard let r = text.range(of: phrase, options: .caseInsensitive) else { return nil }
        return parse(String(text[r.upperBound...]))?.time
    }
}

enum Dates {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Finds dates like "Nov. 16" or "December 4" and picks the year closest to `now`.
    static func all(in text: String, near now: Date) -> [DayKey] {
        let pattern = #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b"#
        let today = Seattle.day(of: now)
        return Regex.allMatches(pattern, in: text).compactMap { g in
            guard let mi = months.firstIndex(of: g[1].lowercased().prefix(3).description),
                  let d = Int(g[2]), (1...31).contains(d)
            else { return nil }
            let candidates = [today.year - 1, today.year, today.year + 1].map {
                DayKey(year: $0, month: mi + 1, day: d)
            }
            return candidates.min { abs(Seattle.daysBetween(today, $0)) < abs(Seattle.daysBetween(today, $1)) }
        }
    }
}
