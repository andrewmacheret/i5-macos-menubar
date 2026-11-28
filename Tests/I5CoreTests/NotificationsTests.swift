import Foundation
import Testing
@testable import I5Core

@Suite struct NotificationsTests {
    /// The regular schedule from Tue, Nov 17 through Sun, Nov 29, closing early at 9 PM on Nov 18,
    /// with the server's Thanksgiving doubt
    let week: Timeline = {
        var segments: [Segment] = []
        var day: DayKey = "2026-11-17"
        let last: DayKey = "2026-11-30"
        func add(_ start: Moment, _ end: Moment, _ status: LaneStatus) {
            if let prev = segments.last, prev.status == status, prev.end == start {
                segments[segments.count - 1].end = end
            } else if end > start {
                segments.append(Segment(start: start, end: end, status: status))
            }
        }
        while day < last {
            var cursor = Seattle.startOfDay(day)
            let windows = Seattle.isWeekend(day) ? WeeklySchedule.builtIn.weekend : WeeklySchedule.builtIn.weekday
            for w in windows {
                let end = day == "2026-11-18" && w.status == .northbound ? hm(21) : w.end
                add(cursor, Seattle.instant(day, w.start), .closed)
                add(Seattle.instant(day, w.start), Seattle.instant(day, end), w.status)
                cursor = Seattle.instant(day, end)
            }
            day = Seattle.addDays(day, 1)
            add(cursor, Seattle.startOfDay(day), .closed)
        }
        return timeline(
            doubts: [doubt("2026-11-26T00:00", "2026-11-28T00:00", title: "No word yet on Thanksgiving", source: .holiday)],
            horizon: Horizon(start: t("2026-11-17T00:00"), end: Seattle.startOfDay(last)),
            segments: segments
        )
    }()

    /// The app's view at `now`. By default the server read WSDOT 5 minutes earlier, so it's fresh.
    func at(_ now: Moment, fetchedAt: Moment? = nil, refreshing: Bool = false, published: Timeline? = nil) -> Snapshot {
        Snapshot(status: status(now, published: published ?? week, fetchedAt: fetchedAt), now: now, refreshing: refreshing)
    }

    func seen(_ s: Snapshot) -> Notifications.Seen { Notifications.seen(s.check, next: s.next) }

    func decide(_ old: Notifications.Seen?, _ s: Snapshot) -> Notifications.Message? {
        Notifications.decide(old, check: s.check, next: s.next, now: s.now)
    }

    @Test func reportsDirectionChangeOnTime() {
        let before = at(t("2026-11-19T04:50"))
        let after = at(t("2026-11-19T05:00"))
        #expect(decide(seen(before), after) == Notifications.Message("I-5 express lanes now southbound", "Closes at 11:00 AM"))
    }

    @Test func skipsOldNews() {
        // The Mac slept through the 5 a.m. switch and woke at 6:30
        let before = at(t("2026-11-19T04:50"))
        #expect(decide(seen(before), at(t("2026-11-19T06:30"))) == nil)
    }

    @Test func skipsShortClosedGap() {
        let after = at(t("2026-11-19T11:00"))
        #expect(decide(seen(at(t("2026-11-19T10:55"))), after) == nil)
        #expect(decide(seen(after), at(t("2026-11-19T11:15")))?.title == "I-5 express lanes now northbound")
    }

    @Test func reportsEarlyClosure() {
        let before = at(t("2026-11-18T20:30"))
        let after = at(t("2026-11-18T21:00"))
        #expect(decide(seen(before), after) == Notifications.Message("I-5 express lanes closed", "Opens southbound at 5:00 AM tomorrow"))
    }

    @Test func reportsLosingConfidenceWhenLanesWouldOpen() {
        let old = seen(at(t("2026-11-25T22:00")))
        #expect(old.verdict == .confident)
        // Thanksgiving's doubt starts at midnight, but the lanes are closed until 5 a.m.
        let midnight = at(t("2026-11-26T00:00"))
        #expect(Notifications.waiting(midnight.check))
        #expect(decide(old, midnight) == nil)
        #expect(decide(old, at(t("2026-11-26T05:00")))
            == Notifications.Message("Can't confirm the I-5 express lanes", "No word yet on Thanksgiving"))
    }

    @Test func quietWhenOnlyTheDataIsOld() {
        // Offline, or the server is stuck, so old data alone doesn't notify
        let before = at(t("2026-11-19T06:00"))
        let after = at(t("2026-11-19T09:00"), fetchedAt: t("2026-11-19T06:00"))
        #expect(after.check.verdict == .uncertain)
        #expect(Notifications.waiting(after.check))
        #expect(decide(seen(before), after) == nil)
    }

    @Test func quietWhileChecking() {
        let stale = t("2026-11-19T01:00")
        let before = at(t("2026-11-19T04:55"), fetchedAt: stale)
        let after = at(t("2026-11-19T05:00"), fetchedAt: stale, refreshing: true)
        #expect(after.check.verdict == .checking)
        #expect(decide(seen(before), after) == nil)
        #expect(decide(nil, after) == nil)
    }

    @Test func quietWhileTheServerReadsANewPage() {
        var reading = week
        reading.doubts.append(doubt("2026-11-19T12:00", "2026-11-19T13:00", title: "Checking WSDOT's latest update", checking: true))
        let before = at(t("2026-11-19T11:55"), published: reading)
        let after = at(t("2026-11-19T12:05"), published: reading)
        #expect(after.check.verdict == .checking)
        #expect(Notifications.waiting(after.check))
        #expect(decide(seen(before), after) == nil)
    }

    @Test func messagesForEachKindOfChange() {
        let now = t("2026-11-19T11:15")
        #expect(Notifications.change(.northbound, next: Change(at: t("2026-11-19T23:00"), to: .closed), now: now).body == "Closes at 11:00 PM")
        #expect(Notifications.change(.southbound, next: Change(at: t("2026-11-19T23:00"), to: .northbound), now: now).body == "Switches northbound at 11:00 PM")
        #expect(Notifications.change(.northbound, next: Change(at: t("2026-11-20T00:00"), to: .unknown), now: now).body
            == "Schedule unknown after 12:00 AM tomorrow")
    }
}
