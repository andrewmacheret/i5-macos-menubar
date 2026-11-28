import Foundation

public enum Format {
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "9:00 PM" in Seattle time
    public static func clock(_ ms: Moment) -> String {
        let t = Seattle.time(ms)
        let h = t / 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, t % 60, h < 12 ? "AM" : "PM")
    }

    /// "Today", "Tomorrow" or "Thu"
    public static func dayName(_ ms: Moment, now: Moment) -> String {
        let day = Seattle.day(ms)
        switch Seattle.daysBetween(Seattle.day(now), day) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return weekdays[Seattle.weekday(day)]
        }
    }

    /// "9:00 PM", "5:00 AM tomorrow", "8:00 AM Sat", or "8:00 AM Sat, Dec 12" once it's a week or more away
    public static func when(_ ms: Moment, now: Moment) -> String {
        let diff = Seattle.daysBetween(Seattle.day(now), Seattle.day(ms))
        if diff >= 7 || diff <= -7 { return "\(clock(ms)) \(shortDate(ms))" }
        let day = dayName(ms, now: now)
        if day == "Today" { return clock(ms) }
        return "\(clock(ms)) \(day == "Tomorrow" ? "tomorrow" : day)"
    }

    /// "Thu, Nov 19"
    public static func shortDay(_ day: DayKey) -> String {
        let d = Seattle.splitDay(day)
        return "\(weekdays[Seattle.weekday(day)]), \(months[max(0, min(11, d.month - 1))]) \(d.day)"
    }

    public static func shortDate(_ ms: Moment) -> String { shortDay(Seattle.day(ms)) }

    /// "4h 5m", "12m", "2d 3h"
    public static func countdown(to: Moment, from: Moment) -> String {
        let total = max(0, floorDiv(to - from, 60_000))
        let d = total / (24 * 60), h = (total / 60) % 24, m = total % 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(max(m, 1))m"
    }
}
