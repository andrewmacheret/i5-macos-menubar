import Foundation
import Testing
@testable import I5Core

@Suite struct AlertsTests {
    let info: ExpressLanesInfo

    init() throws {
        info = Parser.parse(html: try fixture(), now: seattle(2026, 11, 18, 10))
    }

    struct Moment {
        var check: Assessment
        var next: Change?
        var now: Date
    }

    /// The app's view at `now`. By default the data was read 5 minutes earlier, so it's fresh.
    func at(_ now: Date, readAt: Date? = nil, refreshing: Bool = false) -> Moment {
        let r = FetchResult(info: info, source: .live(readAt ?? now.addingTimeInterval(-5 * 60)))
        return Moment(check: Trust.assess(r, now: now, refreshing: refreshing),
                      next: Engine(info: info).upcomingChanges(from: now, limit: 1).first, now: now)
    }

    func seen(_ m: Moment) -> Alerts.Seen { Alerts.seen(m.check, next: m.next) }

    func decide(_ old: Alerts.Seen?, _ m: Moment) -> Alerts.Message? {
        Alerts.decide(old, check: m.check, next: m.next, now: m.now)
    }

    @Test func reportsDirectionChangeOnTime() {
        let before = at(seattle(2026, 11, 19, 4, 50))
        let after = at(seattle(2026, 11, 19, 5))
        #expect(decide(seen(before), after) == Alerts.Message("I-5 express lanes now southbound", "Closes at 11:00 AM"))
    }

    @Test func skipsOldNews() {
        // The Mac slept through the 5 a.m. switch and woke at 6:30
        let before = at(seattle(2026, 11, 19, 4, 50))
        #expect(decide(seen(before), at(seattle(2026, 11, 19, 6, 30))) == nil)
    }

    @Test func skipsShortClosedGap() {
        let after = at(seattle(2026, 11, 19, 11))
        #expect(decide(seen(at(seattle(2026, 11, 19, 10, 55))), after) == nil)
        #expect(decide(seen(after), at(seattle(2026, 11, 19, 11, 15)))?.title == "I-5 express lanes now northbound")
    }

    @Test func reportsEarlyClosure() {
        let before = at(seattle(2026, 11, 18, 20, 30))
        let after = at(seattle(2026, 11, 18, 21))
        #expect(decide(seen(before), after) == Alerts.Message("I-5 express lanes closed", "Opens southbound at 5:00 AM tomorrow"))
    }

    @Test func reportsLosingConfidenceWhenLanesWouldOpen() {
        let old = seen(at(seattle(2026, 11, 25, 22)))
        // Thanksgiving starts at midnight, but the lanes are posted closed until 5 a.m.
        let midnight = at(seattle(2026, 11, 26, 0))
        #expect(Alerts.waiting(midnight.check))
        #expect(decide(old, midnight) == nil)
        #expect(decide(old, at(seattle(2026, 11, 26, 5)))
            == Alerts.Message("Can't confirm the I-5 express lanes", "Thanksgiving may run a holiday schedule"))
    }

    @Test func quietWhenOnlyTheDataIsOld() {
        // Offline or just woken up, old data alone doesn't notify
        let before = at(seattle(2026, 11, 19, 6))
        let after = at(seattle(2026, 11, 19, 9), readAt: seattle(2026, 11, 19, 6))
        #expect(after.check.verdict == .uncertain)
        #expect(Alerts.waiting(after.check))
        #expect(decide(seen(before), after) == nil)
    }

    @Test func quietWhileChecking() {
        let stale = seattle(2026, 11, 19, 1)
        let before = at(seattle(2026, 11, 19, 4, 55), readAt: stale)
        let after = at(seattle(2026, 11, 19, 5), readAt: stale, refreshing: true)
        #expect(after.check.verdict == .checking)
        #expect(decide(seen(before), after) == nil)
        #expect(decide(nil, after) == nil)
    }
}
