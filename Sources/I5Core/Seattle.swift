import Foundation

/// Seattle time helpers. The lanes run on Seattle time no matter where the Mac is.
public enum Seattle {
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static let minute = 60_000
    static let hour = 60 * minute
    static let day = 24 * hour

    /// Minutes Seattle is ahead of UTC at a moment, like -480 in winter
    public static func offsetMinutes(_ ms: Moment) -> Int {
        // Seattle's clock only changes on the hour in UTC
        let hourStart = floorDiv(ms, hour) * hour
        return timeZone.secondsFromGMT(for: Date(moment: hourStart)) / 60
    }

    public static func dayKey(_ year: Int, _ month: Int, _ day: Int) -> DayKey {
        String(format: "%d-%02d-%02d", year, month, day)
    }

    public static func splitDay(_ key: DayKey) -> (year: Int, month: Int, day: Int) {
        let p = key.split(separator: "-").map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    /// Nil for dates that don't exist, like Feb. 30
    public static func validDay(_ year: Int, _ month: Int, _ day: Int) -> DayKey? {
        let c = civil(daysFromCivil(year, month, day))
        return c.month == month && c.day == day ? dayKey(year, month, day) : nil
    }

    private static func days(_ key: DayKey) -> Int {
        let d = splitDay(key)
        return daysFromCivil(d.year, d.month, d.day)
    }

    private static func key(days: Int) -> DayKey {
        let c = civil(days)
        return dayKey(c.year, c.month, c.day)
    }

    public static func addDays(_ key: DayKey, _ n: Int) -> DayKey { Seattle.key(days: days(key) + n) }

    public static func daysBetween(_ a: DayKey, _ b: DayKey) -> Int { days(b) - days(a) }

    /// 0 is Sunday
    public static func weekday(_ key: DayKey) -> Int {
        // Jan 1, 1970 was a Thursday
        ((days(key) + 4) % 7 + 7) % 7
    }

    public static func isWeekend(_ key: DayKey) -> Bool { weekday(key) == 0 || weekday(key) == 6 }

    /// The Seattle wall clock at a moment, as milliseconds that read as Seattle time in UTC
    private static func wallClock(_ ms: Moment) -> Int { ms + offsetMinutes(ms) * minute }

    public static func day(_ ms: Moment) -> DayKey { key(days: floorDiv(wallClock(ms), day)) }

    public static func time(_ ms: Moment) -> TimeOfDay {
        let w = wallClock(ms)
        return (w - floorDiv(w, day) * day) / minute
    }

    /// The moment a Seattle wall clock shows `t` on `key`. `endOfDay` means the next midnight.
    /// Like java.time, a time skipped by spring forward moves later by an hour,
    /// and a time repeated by fall back picks the first one.
    public static func instant(_ key: DayKey, _ t: TimeOfDay) -> Moment {
        if t >= 24 * 60 { return startOfDay(addDays(key, 1)) }
        let wall = days(key) * day + t * minute
        let before = offsetMinutes(wall - day)
        var valid: [Moment] = []
        for off in Set([before, offsetMinutes(wall + day)]) {
            let ms = wall - off * minute
            if offsetMinutes(ms) == off { valid.append(ms) }
        }
        return valid.min() ?? wall - before * minute
    }

    public static func startOfDay(_ key: DayKey) -> Moment { instant(key, 0) }

    /// True when the Mac's clock isn't on Seattle time right now
    public static func differsFromLocal(_ ms: Moment) -> Bool {
        TimeZone.current.secondsFromGMT(for: Date(moment: ms)) / 60 != offsetMinutes(ms)
    }

    // Days since Jan 1, 1970 for a calendar date and back, from Howard Hinnant's date algorithms

    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}

/// Division that rounds down, like Math.floor(a / b), so moments before 1970 still work
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
