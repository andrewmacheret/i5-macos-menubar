import Foundation

public enum Format {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Seattle.timeZone
        f.dateFormat = pattern
        return f
    }

    private static let clockFormatter = formatter("h:mm a")
    private static let weekdayFormatter = formatter("EEE")
    private static let shortDateFormatter = formatter("EEE, MMM d")

    public static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// "Today", "Tomorrow" or "Thu"
    public static func dayName(_ date: Date, now: Date) -> String {
        let diff = Seattle.daysBetween(Seattle.day(of: now), Seattle.day(of: date))
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return weekdayFormatter.string(from: date)
        }
    }

    /// "9:00 PM", "5:00 AM tomorrow", "8:00 AM Sat"
    public static func when(_ date: Date, now: Date) -> String {
        let day = dayName(date, now: now)
        return day == "Today" ? clock(date) : "\(clock(date)) \(day == "Tomorrow" ? "tomorrow" : day)"
    }

    public static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }

    public static func shortDate(_ day: DayKey) -> String {
        Seattle.date(day, TimeOfDay(12)).map(shortDate) ?? "\(day.month)/\(day.day)"
    }

    /// "in 4h 5m", "in 12m", "in 2d 3h"
    public static func countdown(to date: Date, from now: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now) / 60))
        let d = total / (24 * 60), h = (total / 60) % 24, m = total % 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(max(m, 1))m"
    }
}
