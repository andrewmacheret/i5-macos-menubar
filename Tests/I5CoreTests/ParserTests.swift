import Foundation
import Testing
@testable import I5Core

/// A moment in Seattle time.
func seattle(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    Seattle.date(DayKey(year: y, month: mo, day: d), TimeOfDay(h, mi))!
}

func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

func fixture() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/express-lanes-2026-11-18", withExtension: "html"))
    return try String(contentsOf: url, encoding: .utf8)
}

/// Wraps snippets in the page's real outline so tests can tweak one part.
func page(schedule: String = defaultSchedule, special: String = "") -> String {
    """
    <h2>Main navigation</h2>
    <h2>I-5 express lanes schedule</h2>\(schedule)
    <h2>Special events schedule</h2>\(special)
    <h2>I-5 express lanes map</h2><h2>Footer</h2><p>Copyright Nov. 1</p>
    """
}

let defaultSchedule = """
<h3>Monday-Friday</h3><ul><li>Southbound - 5 a.m. to 11 a.m.</li><li>Northbound - 11:15 a.m. to 11 p.m.</li><li>Closed: 11 p.m. - 5 a.m.</li></ul>
<h3>Saturday &amp; Sunday</h3><ul><li>Southbound - 8 a.m. to 1:30 p.m.</li><li>Northbound - 1:45 to 11 p.m.</li></ul>
"""

@Suite struct ParserTests {
    let now = seattle(2026, 11, 18, 16, 55)

    @Test func readsWeeklySchedule() throws {
        let info = Parser.parse(html: try fixture(), now: now)
        #expect(info.scheduleFromPage)
        #expect(info.schedule == .builtIn)
        #expect(info.warnings.isEmpty)
    }

    @Test func readsEarlyCloses() throws {
        let info = Parser.parse(html: try fixture(), now: now)
        #expect(info.earlyCloses.count == 19)
        #expect(info.earlyCloses.allSatisfy { $0.time == TimeOfDay(21) })
        #expect(info.earlyCloses.first?.day == day(2026, 11, 16))
        // January rolls into next year
        #expect(info.earlyCloses.last?.day == day(2027, 1, 6))
    }

    @Test func earlyCloseWithItsOwnTime() {
        let html = page(special: """
        <h3>Express lanes closing early</h3><p>The I-5 express lanes will close at 9 p.m. on the dates below.</p>
        <ul><li>Monday, Nov. 30</li><li>Tuesday, Dec. 1 at 8 p.m.</li></ul>
        """)
        let info = Parser.parse(html: html, now: now)
        #expect(info.earlyCloses == [EarlyClose(day: day(2026, 11, 30), time: TimeOfDay(21)),
                                     EarlyClose(day: day(2026, 12, 1), time: TimeOfDay(20))])
    }

    @Test func earlyCloseWithoutTime() {
        let html = page(special: "<h3>Express lanes closing early</h3><p>The lanes will close early.</p><ul><li>Monday, Nov. 30</li></ul>")
        #expect(Parser.parse(html: html, now: now).earlyCloses == [EarlyClose(day: day(2026, 11, 30), time: nil)])
    }

    @Test func readsWeekendClosure() throws {
        let info = Parser.parse(html: try fixture(), now: now)
        let e = try #require(info.events.first)
        let c = try #require(e.closure)
        #expect(c.start == seattle(2026, 12, 4, 23))
        #expect(c.end == seattle(2026, 12, 7, 4))
        #expect(e.days == DayRange(first: day(2026, 12, 4), last: day(2026, 12, 7)))
        #expect(e.link?.absoluteString.contains("ship-canal-bridge") == true)
    }

    @Test func closureWithoutTimesIsNotGuessed() {
        let html = page(special: "<h3>Full express lanes closure</h3><p>The lanes will be closed Dec. 12 and Dec. 13.</p>")
        let e = Parser.parse(html: html, now: now).events.first
        #expect(e?.closure == nil)
        #expect(e?.days == DayRange(first: day(2026, 12, 12), last: day(2026, 12, 13)))
    }

    @Test func readsAdvisoryDates() throws {
        let info = Parser.parse(html: try fixture(), now: now)
        let a = try #require(info.advisories.first)
        #expect(a.text.hasPrefix("Please note"))
        #expect(a.days == DayRange(first: day(2026, 11, 16), last: day(2026, 11, 17)))
        #expect(a.isOver(before: day(2026, 11, 18)))
        #expect(!a.isOver(before: day(2026, 11, 17)))
    }

    @Test func untilFurtherNoticeHasNoEnd() {
        let html = page(schedule: "<p>As of Nov. 16 the express lanes are closed until further notice.</p>" + defaultSchedule)
        let a = Parser.parse(html: html, now: now).advisories.first
        #expect(a?.days == DayRange(first: day(2026, 11, 16), last: nil))
        #expect(a?.isOver(before: day(2026, 12, 25)) == false)
    }

    @Test func flagsUnknownPageParts() {
        let html = page(schedule: defaultSchedule + "<h3>Holidays</h3><ul><li>Southbound only, all day</li></ul>")
        let info = Parser.parse(html: html, now: now)
        #expect(info.scheduleFromPage)
        #expect(info.warnings.contains { $0.contains("Holidays") })
        #expect(info.warnings.contains { $0.contains("Southbound only, all day") })
    }

    @Test func onlyReadsTheExpressLanesPart() {
        // The footer's "Nov. 1" must not become a notice
        let info = Parser.parse(html: page(), now: now)
        #expect(info.advisories.isEmpty)
        #expect(info.warnings.isEmpty)
    }

    @Test func windowFormats() {
        #expect(Parser.window(from: "Northbound - 1:45 to 11 p.m.") == LaneWindow(.northbound, TimeOfDay(13, 45), TimeOfDay(23)))
        #expect(Parser.window(from: "Southbound - 10 to 2 p.m.") == LaneWindow(.southbound, TimeOfDay(10), TimeOfDay(14)))
        #expect(Parser.window(from: "Southbound - 24 hours a day") == LaneWindow(.southbound, .midnight, .endOfDay))
        #expect(Parser.window(from: "Northbound - 11 a.m. to midnight") == LaneWindow(.northbound, TimeOfDay(11), .endOfDay))
        #expect(Parser.window(from: "Closed: 11 p.m. - 5 a.m.") == nil)
    }

    @Test func garbageFallsBackToBuiltIn() {
        let info = Parser.parse(html: "<html><p>nothing here</p></html>")
        #expect(!info.scheduleFromPage)
        #expect(info.schedule == .builtIn)
        #expect(!info.warnings.isEmpty)
    }
}
