import Foundation
import Testing
@testable import I5Core

// The same checks as i5-server-lambdas/test/core.test.ts, so the Swift copy behaves like the server's core

@Suite struct TimesInWordsTests {
    let now = t("2026-11-18T12:00") // a Wednesday

    @Test func sayTheDayOnlyWhenItIsNotToday() {
        #expect(Format.when(t("2026-11-18T21:00"), now: now) == "9:00 PM")
        #expect(Format.when(t("2026-11-19T05:00"), now: now) == "5:00 AM tomorrow")
        #expect(Format.when(t("2026-11-24T08:00"), now: now) == "8:00 AM Tue")
    }

    @Test func giveTheDateOnceItIsAWeekOrMoreAway() {
        #expect(Format.when(t("2026-11-25T08:00"), now: now) == "8:00 AM Wed, Nov 25")
        #expect(Format.when(t("2027-01-01T00:00"), now: now) == "12:00 AM Fri, Jan 1")
        #expect(Format.when(t("2026-11-10T08:00"), now: now) == "8:00 AM Tue, Nov 10")
    }

    @Test func countdowns() {
        #expect(Format.countdown(to: now + (4 * 60 + 5) * 60_000, from: now) == "4h 5m")
        #expect(Format.countdown(to: now + 12 * 60_000, from: now) == "12m")
        #expect(Format.countdown(to: now + 30_000, from: now) == "1m")
        #expect(Format.countdown(to: now + (51 * 60) * 60_000, from: now) == "2d 3h")
    }

    @Test func wallClockTimesOnDaylightSavingDays() {
        let iso = ISO8601DateFormatter()
        func at(_ s: String) -> Moment { iso.date(from: s)!.moment }
        // Mar 8, 2026 jumps from 2 AM to 3 AM, so 2:30 AM doesn't exist and moves to 3:30
        #expect(Seattle.instant("2026-03-08", hm(10)) == at("2026-03-08T10:00:00-07:00"))
        #expect(Seattle.instant("2026-03-08", hm(2, 30)) == at("2026-03-08T03:30:00-07:00"))
        // Nov 1, 2026 goes through 1 AM twice. Use the first one
        #expect(Seattle.instant("2026-11-01", hm(1, 30)) == at("2026-11-01T01:30:00-07:00"))
        #expect(Seattle.instant("2026-11-01", hm(10)) == at("2026-11-01T10:00:00-08:00"))
        #expect(Seattle.day(at("2026-11-19T07:59:00Z")) == "2026-11-18")
        #expect(Seattle.time(at("2026-11-19T07:59:00Z")) == hm(23, 59))
    }

    @Test func calendarDays() {
        #expect(Seattle.addDays("2026-12-31", 1) == "2027-01-01")
        #expect(Seattle.addDays("2028-03-01", -1) == "2028-02-29")
        #expect(Seattle.daysBetween("2026-11-18", "2027-01-01") == 44)
        #expect(Seattle.weekday("2026-11-18") == 3)
        #expect(Seattle.isWeekend("2026-11-21"))
        #expect(Seattle.validDay(2026, 2, 30) == nil)
        #expect(Format.shortDay("2026-11-19") == "Thu, Nov 19")
    }
}

@Suite struct TimelineTests {
    let p = timeline()

    @Test func findsTheStatusAtAMomentUnknownOutsideTheTimeline() {
        #expect(p.status(at: t("2026-11-18T05:00")) == .southbound)
        #expect(p.status(at: t("2026-11-18T04:59")) == .closed)
        #expect(p.status(at: t("2026-11-18T21:00")) == .closed)
        #expect(p.status(at: t("2026-11-16T12:00")) == .unknown)
        #expect(p.status(at: t("2026-11-20T00:00")) == .unknown)
    }

    @Test func listsTheNextChangesEndingWithUnknownAtTheEndOfTheTimeline() {
        #expect(p.upcomingChanges(from: t("2026-11-18T12:00"), limit: 3) == [
            Change(at: t("2026-11-18T21:00"), to: .closed),
            Change(at: t("2026-11-19T05:00"), to: .southbound),
            Change(at: t("2026-11-20T00:00"), to: .unknown),
        ])
        #expect(p.upcomingChanges(from: t("2026-11-18T12:00"), limit: 1) == [Change(at: t("2026-11-18T21:00"), to: .closed)])
    }

    @Test func findsTheLastChange() {
        #expect(p.lastChange(at: t("2026-11-18T12:00")) == t("2026-11-18T11:15"))
        #expect(p.lastChange(at: t("2026-11-17T01:00")) == nil)
    }

    @Test func drawsADayInWallClockMinutes() {
        #expect(p.daySegments("2026-11-18") == [
            DaySegment(start: 0, end: 300, status: .closed),
            DaySegment(start: 300, end: 660, status: .southbound),
            DaySegment(start: 660, end: 675, status: .closed),
            DaySegment(start: 675, end: 1260, status: .northbound),
            DaySegment(start: 1260, end: 1440, status: .closed),
        ])
        #expect(p.daySegments("2026-11-20") == [DaySegment(start: 0, end: 1440, status: .unknown)])
        #expect(p.daySegments("2026-11-16") == [DaySegment(start: 0, end: 1440, status: .unknown)])
    }

    @Test(arguments: ["2026-11-01", "2027-03-14"])
    func fitsFallBackAndSpringForwardDaysInto24Hours(day: String) {
        let start = Seattle.startOfDay(day), end = Seattle.startOfDay(Seattle.addDays(day, 1))
        let q = timeline(horizon: Horizon(start: start, end: end), segments: [
            Segment(start: start, end: Seattle.instant(day, 8 * 60), status: .closed),
            Segment(start: Seattle.instant(day, 8 * 60), end: end, status: .southbound),
        ])
        #expect(q.daySegments(day) == [
            DaySegment(start: 0, end: 480, status: .closed),
            DaySegment(start: 480, end: 1440, status: .southbound),
        ])
    }

    @Test func findsDoubtsAtAMoment() {
        let q = timeline(doubts: [doubt("2026-11-18T20:00", "2026-11-18T22:00")])
        #expect(q.doubts(at: t("2026-11-18T21:00")).count == 1)
        #expect(q.doubts(at: t("2026-11-18T22:00")).isEmpty)
    }
}

@Suite struct AssessTests {
    let now = t("2026-11-18T12:00")

    @Test func isConfidentWithFreshDataAndNoDoubts() {
        let a = Trust.assess(status(now), now: now)
        #expect(a == Assessment(verdict: .confident, scheduled: .northbound, concerns: []))
        #expect(a.shown == .northbound)
    }

    @Test func isNotConfidentWhenNothingHasBeenPublished() {
        let a = Trust.assess(status(now, published: nil), now: now)
        #expect(a.verdict == .uncertain)
        #expect(a.scheduled == .unknown)
        #expect(a.shown == nil)
    }

    @Test func isNotConfidentWhenThePageHasNotBeenReadIn2Hours() {
        let a = Trust.assess(status(now, fetchedAt: now - Trust.maxAge - 60_000, error: "WSDOT returned HTTP 503"), now: now)
        #expect(a.verdict == .uncertain)
        #expect(a.concerns.first?.title == "Data is 2h 1m old")
        #expect(a.concerns.first?.detail.contains("WSDOT returned HTTP 503") == true)
        // Just inside the limit is fine
        #expect(Trust.assess(status(now, fetchedAt: now - Trust.maxAge), now: now).verdict == .confident)
    }

    @Test func noticesADeviceClockThatIsBehind() {
        let a = Trust.assess(status(now, fetchedAt: now + 10 * 60_000), now: now)
        #expect(a.concerns.map(\.title).contains("This device's clock is off"))
        // A few minutes ahead is normal clock drift
        #expect(Trust.assess(status(now, fetchedAt: now + 4 * 60_000), now: now).verdict == .confident)
    }

    @Test func isNotConfidentOutsideTheTimeline() {
        let later = t("2026-11-20T12:00")
        let a = Trust.assess(status(later), now: later)
        #expect(a.verdict == .uncertain)
        #expect(a.concerns.map(\.title).contains("No schedule for today"))
    }

    @Test func showsTheServerDoubtsThatApplyNow() {
        let p = timeline(doubts: [doubt("2026-11-18T11:00", "2026-11-18T13:00", title: "Approximate")])
        let a = Trust.assess(status(now, published: p), now: now)
        #expect(a.verdict == .uncertain)
        #expect(a.concerns.map(\.title) == ["Approximate"])
        #expect(a.concerns.first?.checking == false)
        #expect(a.concerns.first?.link == Sources.expressLanes)
    }

    @Test func saysCheckingWhenTheOnlyDoubtsAreADocumentBeingRead() {
        let p = timeline(doubts: [doubt("2026-11-18T11:00", "2026-11-20T00:00", checking: true)])
        #expect(Trust.assess(status(now, published: p), now: now).verdict == .checking)
        let q = timeline(doubts: [doubt("2026-11-18T11:00", "2026-11-20T00:00", checking: true),
                                  doubt("2026-11-18T11:00", "2026-11-18T13:00")])
        #expect(Trust.assess(status(now, published: q), now: now).verdict == .uncertain)
    }

    @Test func saysCheckingForOldDataOnlyWhileTheAppIsDownloading() {
        let old = status(now, fetchedAt: now - 3 * 60 * 60_000)
        #expect(Trust.assess(old, now: now).verdict == .uncertain)
        #expect(Trust.assess(old, now: now, refreshing: true).verdict == .checking)
        #expect(Trust.assess(.empty, now: now, refreshing: true).verdict == .checking)
        // A refresh can't fix a doubt or a wrong clock
        let p = timeline(doubts: [doubt("2026-11-18T11:00", "2026-11-18T13:00")])
        #expect(Trust.assess(status(now, published: p), now: now, refreshing: true).verdict == .uncertain)
        #expect(Trust.assess(status(now, fetchedAt: now + 10 * 60_000), now: now, refreshing: true).verdict == .uncertain)
    }
}

@Suite struct LiveSensorTests {
    func reading(_ at: String, _ northbound: Int?, _ southbound: Int?) -> LiveReading {
        LiveReading(at: t(at), northbound: northbound, southbound: southbound, trips: nil)
    }

    func concerns(_ now: String, _ live: LiveReading) -> [Concern] {
        Trust.liveConcerns(status(t(now), live: live), now: t(now))
    }

    @Test func readsWhichWayTrafficIsMoving() {
        #expect(Trust.liveReadingStatus(reading("2026-11-18T12:00", 23, 0)) == .northbound)
        #expect(Trust.liveReadingStatus(reading("2026-11-18T12:00", 0, 19)) == .southbound)
        #expect(Trust.liveReadingStatus(reading("2026-11-18T12:00", nil, 0)) == Trust.LiveSeen.none)
        #expect(Trust.liveReadingStatus(reading("2026-11-18T12:00", 23, 19)) == .both)
    }

    @Test func agreesQuietlyWithTheTimeline() {
        #expect(concerns("2026-11-18T14:00", reading("2026-11-18T13:55", 23, 0)).isEmpty)
    }

    @Test func flagsTrafficGoingTheOtherWay() {
        let c = concerns("2026-11-18T14:00", reading("2026-11-18T13:55", 0, 19))
        #expect(c.map(\.title) == ["WSDOT's sensors show southbound traffic"])
        #expect(c.first?.checking == false)
        #expect(c.first?.detail.contains("should be northbound") == true)
        #expect(c.first?.link == Sources.travelMap)
        let now = t("2026-11-18T14:00")
        #expect(Trust.assess(status(now, live: reading("2026-11-18T13:55", 0, 19)), now: now).verdict == .uncertain)
    }

    @Test func flagsNoTrafficWhileTheLanesShouldBeOpen() {
        #expect(concerns("2026-11-18T14:00", reading("2026-11-18T13:55", 0, 0)).map(\.title) == ["No traffic measured"])
    }

    @Test func flagsTrafficWhileTheLanesShouldBeClosed() {
        #expect(concerns("2026-11-19T02:00", reading("2026-11-19T01:55", 21, 0)).map(\.title) == ["WSDOT's sensors show northbound traffic"])
        #expect(concerns("2026-11-19T02:00", reading("2026-11-19T01:55", 0, 0)).isEmpty)
    }

    @Test func ignoresReadingsSoonAfterASwitchSinceTheSensorsLag() {
        // The lanes closed early at 9 p.m., and the sensors still see the last northbound trips
        #expect(concerns("2026-11-18T21:20", reading("2026-11-18T21:15", 23, 0)).isEmpty)
        #expect(concerns("2026-11-18T21:40", reading("2026-11-18T21:35", 23, 0)).count == 1)
    }

    @Test func ignoresOldReadingsReadingsFromTheFutureAndBoth() {
        #expect(concerns("2026-11-18T14:00", reading("2026-11-18T13:00", 0, 19)).isEmpty)
        #expect(concerns("2026-11-18T14:00", reading("2026-11-18T14:20", 0, 19)).isEmpty)
        #expect(concerns("2026-11-18T14:00", reading("2026-11-18T13:55", 23, 19)).isEmpty)
    }
}

@Suite struct SnapshotTests {
    @Test func worksOutTheNextChangeAndDoubtfulDays() {
        let now = t("2026-11-18T12:00")
        let p = timeline(doubts: [doubt("2026-11-19T06:00", "2026-11-19T07:00")])
        let s = Snapshot(status: status(now, published: p), now: now)
        #expect(s.next == Change(at: t("2026-11-18T21:00"), to: .closed))
        #expect(s.nextText == "Closes at 9:00 PM")
        #expect(s.doubtfulDays == ["2026-11-19"])
        #expect(s.tomorrowDoubts.count == 1)
        #expect(s.todaySegments.dropLast().last == DaySegment(start: 675, end: 1260, status: .northbound))
    }

    @Test func copesWithNothingPublished() {
        let now = t("2026-11-18T12:00")
        let s = Snapshot(status: status(now, published: nil), now: now)
        #expect(s.next == nil)
        #expect(s.nextText == "No changes coming up")
        #expect(s.todaySegments == [DaySegment(start: 0, end: 1440, status: .unknown)])
    }

    @Test func switchingSoonOnlyWithin15MinutesOfARealChange() {
        let p = timeline()
        #expect(Snapshot(status: status(t("2026-11-18T20:45"), published: p), now: t("2026-11-18T20:45")).changingSoon)
        #expect(!Snapshot(status: status(t("2026-11-18T20:44"), published: p), now: t("2026-11-18T20:44")).changingSoon)
        // The end of the timeline isn't a change worth a dot
        #expect(!Snapshot(status: status(t("2026-11-19T23:50"), published: p), now: t("2026-11-19T23:50")).changingSoon)
    }

    @Test func verbs() {
        #expect(Snapshot.verb(.northbound, .closed) == "Closes")
        #expect(Snapshot.verb(.closed, .southbound) == "Opens southbound")
        #expect(Snapshot.verb(.southbound, .northbound) == "Switches northbound")
        #expect(Snapshot.verb(.northbound, .unknown) == "Schedule unknown")
    }
}
