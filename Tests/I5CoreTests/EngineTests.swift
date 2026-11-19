import Foundation
import Testing
@testable import I5Core

@Suite struct EngineTests {
    let engine = Engine(info: ExpressLanesInfo(
        earlyCloses: [EarlyClose(day: day(2026, 11, 18), time: TimeOfDay(21)), EarlyClose(day: day(2026, 11, 19), time: nil)],
        events: [SpecialEvent(title: "Weekend closure", detail: "", link: nil,
                              closure: Closure(title: "Weekend closure", start: seattle(2026, 12, 4, 23), end: seattle(2026, 12, 7, 4)))]
    ))

    @Test func passedEarlyCloseDropsOffTheList() {
        #expect(engine.upcomingEarlyCloses(from: seattle(2026, 11, 18, 20)).first?.day == day(2026, 11, 18))
        #expect(engine.upcomingEarlyCloses(from: seattle(2026, 11, 18, 22)).first?.day == day(2026, 11, 19))
    }

    @Test func earlyCloseWithUnknownTimeDoesNotCut() {
        // Trust flags this day. The engine just keeps the normal schedule.
        #expect(engine.status(at: seattle(2026, 11, 19, 22)) == .northbound)
    }

    @Test func daylightSavingDays() {
        // Nov 1, 2026 falls back and Mar 8, 2026 springs forward. Both are Sundays.
        for d in [day(2026, 11, 1), day(2026, 3, 8)] {
            let segs = engine.segments(for: d)
            #expect(segs.map(\.status) == [.closed, .southbound, .closed, .northbound, .closed])
            #expect(segs[1].start == TimeOfDay(8) && segs[1].end == TimeOfDay(13, 30))
            #expect(segs[3].start == TimeOfDay(13, 45) && segs[3].end == TimeOfDay(23))
            #expect(segs.last?.end == .endOfDay)
        }
    }

    @Test func weekday() {
        // Thu Nov 19, 2026
        #expect(engine.status(at: seattle(2026, 11, 19, 4, 59)) == .closed)
        #expect(engine.status(at: seattle(2026, 11, 19, 5)) == .southbound)
        #expect(engine.status(at: seattle(2026, 11, 19, 11, 5)) == .closed)
        #expect(engine.status(at: seattle(2026, 11, 19, 11, 15)) == .northbound)
        #expect(engine.status(at: seattle(2026, 11, 19, 22, 59)) == .northbound)
        #expect(engine.status(at: seattle(2026, 11, 19, 23)) == .closed)
    }

    @Test func weekend() {
        // Sat Nov 21, 2026
        #expect(engine.status(at: seattle(2026, 11, 21, 7, 59)) == .closed)
        #expect(engine.status(at: seattle(2026, 11, 21, 8)) == .southbound)
        #expect(engine.status(at: seattle(2026, 11, 21, 13, 40)) == .closed)
        #expect(engine.status(at: seattle(2026, 11, 21, 14)) == .northbound)
    }

    @Test func earlyClose() {
        #expect(engine.status(at: seattle(2026, 11, 18, 20, 59)) == .northbound)
        #expect(engine.status(at: seattle(2026, 11, 18, 21)) == .closed)
    }

    @Test func fullClosure() {
        // Sat Dec 5 would normally be southbound at 10 a.m.
        #expect(engine.status(at: seattle(2026, 12, 5, 10)) == .closed)
        #expect(engine.status(at: seattle(2026, 12, 7, 5)) == .southbound)
    }

    @Test func upcomingChanges() {
        let changes = engine.upcomingChanges(from: seattle(2026, 11, 18, 16, 55), limit: 3)
        #expect(changes.map(\.to) == [.closed, .southbound, .closed])
        #expect(changes.first?.date == seattle(2026, 11, 18, 21))
        #expect(changes[1].date == seattle(2026, 11, 19, 5))
    }

    @Test func timeline() {
        let segs = engine.segments(for: DayKey(year: 2026, month: 11, day: 19))
        #expect(segs.map(\.status) == [.closed, .southbound, .closed, .northbound, .closed])
        #expect(segs[1].start == TimeOfDay(5) && segs[1].end == TimeOfDay(11))
    }

    @Test func countdownText() {
        let now = seattle(2026, 11, 18, 16, 55)
        #expect(Format.countdown(to: seattle(2026, 11, 18, 21), from: now) == "4h 5m")
        #expect(Format.countdown(to: seattle(2026, 11, 18, 17), from: now) == "5m")
        #expect(Format.when(seattle(2026, 11, 19, 5), now: now) == "5:00 AM tomorrow")
    }
}
