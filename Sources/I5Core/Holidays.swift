import Foundation

/// Holidays when WSDOT may run the lanes differently. WSDOT's page doesn't list
/// holiday schedules, so on these days the app says it can't confirm.
public enum Holidays {
    public static func name(for day: DayKey) -> String? {
        let y = day.year
        var list: [(DayKey, String)] = [
            (observed(DayKey(year: y, month: 1, day: 1)), "New Year's Day"),
            (nth(3, .monday, 1, y), "Martin Luther King Jr. Day"),
            (nth(3, .monday, 2, y), "Presidents Day"),
            (last(.monday, 5, y), "Memorial Day"),
            (observed(DayKey(year: y, month: 6, day: 19)), "Juneteenth"),
            (observed(DayKey(year: y, month: 7, day: 4)), "Independence Day"),
            (nth(1, .monday, 9, y), "Labor Day"),
            (observed(DayKey(year: y, month: 11, day: 11)), "Veterans Day"),
            (nth(4, .thursday, 11, y), "Thanksgiving"),
            (DayKey(year: y, month: 12, day: 24), "Christmas Eve"),
            (observed(DayKey(year: y, month: 12, day: 25)), "Christmas"),
            (DayKey(year: y, month: 12, day: 31), "New Year's Eve"),
        ]
        let thanksgiving = nth(4, .thursday, 11, y)
        if let friday = add(1, to: thanksgiving) { list.append((friday, "Day after Thanksgiving")) }
        // The real date too, when the holiday is observed on another day
        for (m, d, n) in [(1, 1, "New Year's Day"), (6, 19, "Juneteenth"), (7, 4, "Independence Day"), (11, 11, "Veterans Day"), (12, 25, "Christmas")] {
            list.append((DayKey(year: y, month: m, day: d), n))
        }
        return list.first { $0.0 == day }?.1
    }

    private enum Weekday: Int { case sunday = 1, monday = 2, thursday = 5 }

    private static func weekday(_ day: DayKey) -> Int {
        Seattle.date(day, TimeOfDay(12)).map { Seattle.calendar.component(.weekday, from: $0) } ?? 0
    }

    private static func add(_ days: Int, to day: DayKey) -> DayKey? {
        Seattle.date(day, TimeOfDay(12))
            .flatMap { Seattle.calendar.date(byAdding: .day, value: days, to: $0) }
            .map(Seattle.day(of:))
    }

    private static func nth(_ n: Int, _ wd: Weekday, _ month: Int, _ year: Int) -> DayKey {
        var count = 0
        for d in 1...31 {
            let key = DayKey(year: year, month: month, day: d)
            if weekday(key) == wd.rawValue {
                count += 1
                if count == n { return key }
            }
        }
        return DayKey(year: year, month: month, day: 1)
    }

    private static func last(_ wd: Weekday, _ month: Int, _ year: Int) -> DayKey {
        for d in stride(from: 31, through: 1, by: -1) {
            let key = DayKey(year: year, month: month, day: d)
            guard Seattle.day(of: Seattle.date(key, TimeOfDay(12))!) == key else { continue }
            if weekday(key) == wd.rawValue { return key }
        }
        return DayKey(year: year, month: month, day: 1)
    }

    /// Saturday holidays move to Friday, Sunday ones to Monday
    private static func observed(_ day: DayKey) -> DayKey {
        switch weekday(day) {
        case 7: add(-1, to: day) ?? day
        case 1: add(1, to: day) ?? day
        default: day
        }
    }
}
