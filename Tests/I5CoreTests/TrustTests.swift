import Foundation
import Testing
@testable import I5Core

@Suite struct TrustTests {
    let now = seattle(2026, 11, 18, 16, 55)

    func live(_ html: String, at: Date? = nil) -> FetchResult {
        let t = at ?? now
        return FetchResult(info: Parser.parse(html: html, now: t), source: .live(t))
    }

    @Test func todaysRealPageIsConfident() throws {
        // The old Monday notice is over, so it doesn't count
        let check = Trust.assess(live(try fixture()), now: now)
        #expect(check.verdict == .confident)
        #expect(check.shown == .northbound)
    }

    @Test func noticeForTodayBlocksConfidence() throws {
        let check = Trust.assess(live(try fixture(), at: seattle(2026, 11, 17, 8)), now: seattle(2026, 11, 17, 8))
        #expect(check.verdict == .uncertain)
        #expect(check.shown == nil)
        #expect(check.concerns.contains { $0.title == "WSDOT posted a notice" })
    }

    @Test func undatedNoticeBlocksConfidence() {
        let html = page(schedule: "<p>The express lanes are closed for an emergency repair.</p>" + defaultSchedule)
        #expect(Trust.assess(live(html), now: now).verdict == .uncertain)
    }

    @Test func holidayBlocksConfidence() throws {
        let tg = seattle(2026, 11, 26, 10)
        let check = Trust.assess(live(try fixture(), at: tg), now: tg)
        #expect(check.verdict == .uncertain)
        #expect(check.concerns.first?.title.contains("Thanksgiving") == true)
    }

    @Test func closureWithUnclearTimesBlocksThoseDays() {
        let html = page(special: "<h3>Full express lanes closure</h3><p>The lanes will be closed Dec. 12 and Dec. 13.</p>")
        let during = seattle(2026, 12, 12, 10)
        #expect(Trust.assess(live(html, at: during), now: during).verdict == .uncertain)
        let before = seattle(2026, 12, 10, 10)
        #expect(Trust.assess(live(html, at: before), now: before).verdict == .confident)
    }

    @Test func earlyCloseWithoutTimeBlocksThatDay() {
        let html = page(special: "<h3>Express lanes closing early</h3><p>Early closures.</p><ul><li>Wednesday, Nov. 18</li></ul>")
        #expect(Trust.assess(live(html), now: now).verdict == .uncertain)
    }

    @Test func staleData() throws {
        let old = FetchResult(info: Parser.parse(html: try fixture(), now: now), source: .cached(now.addingTimeInterval(-3 * 3600)))
        #expect(Trust.assess(old, now: now).verdict == .uncertain)
        // While a refresh is running it says checking instead
        #expect(Trust.assess(old, now: now, refreshing: true).verdict == .checking)
        let fresh = FetchResult(info: old.info, source: .cached(now.addingTimeInterval(-30 * 60)))
        #expect(Trust.assess(fresh, now: now).verdict == .confident)
    }

    @Test func builtInNeverConfident() {
        let r = FetchResult(info: .builtIn, source: .builtIn)
        #expect(Trust.assess(r, now: now).verdict == .uncertain)
        #expect(Trust.assess(r, now: now, refreshing: true).verdict == .checking)
    }

    @Test func changedPageNeverConfident() throws {
        var r = FetchResult(info: Parser.parse(html: try fixture(), now: now), source: .cached(now))
        r.pageChanged = true
        #expect(Trust.assess(r, now: now, refreshing: true).verdict == .uncertain)
    }

    @Test func futureFetchTimeIsNotTrusted() throws {
        // The clock was set back after the page was read
        let r = FetchResult(info: Parser.parse(html: try fixture(), now: now), source: .cached(now.addingTimeInterval(3600)))
        #expect(Trust.assess(r, now: now).verdict == .uncertain)
        #expect(Trust.assess(r, now: now, refreshing: true).verdict == .checking)
    }

    struct Offline: Error {}

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("i5-\(UUID().uuidString)", isDirectory: true)
    }

    func fetcher(_ dir: URL, _ html: String) -> Fetcher {
        Fetcher(cacheDir: dir) { Data(html.utf8) }
    }

    func offline(_ dir: URL) -> Fetcher {
        Fetcher(cacheDir: dir) { throw Offline() }
    }

    @Test func fetcherKeepsLastGoodCopy() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = await fetcher(dir, try fixture()).load(now: now)
        #expect(good.source == .live(now))

        // The network fails, so the saved copy is used
        let down = await offline(dir).load(now: now.addingTimeInterval(60))
        #expect(down.source == .cached(now))
        #expect(down.error != nil)

        // The page changes into something unreadable. Keep the old copy and say so.
        let changed = await fetcher(dir, "<html>new site</html>").load(now: now.addingTimeInterval(120))
        #expect(changed.source == .cached(now))
        #expect(changed.pageChanged)
        #expect(changed.info.scheduleFromPage)
    }

    @Test func fetcherRemembersChangedPage() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try fixture()
        _ = await fetcher(dir, html).load(now: now)
        _ = await fetcher(dir, "<html>new site</html>").load(now: now.addingTimeInterval(60))

        // After a restart, and after a failed download, the problem is still there
        #expect(fetcher(dir, html).cachedOrBuiltIn(now: now.addingTimeInterval(120)).pageChanged)
        let later = now.addingTimeInterval(180)
        let down = await offline(dir).load(now: later)
        #expect(down.pageChanged)
        #expect(Trust.assess(down, now: later).verdict == .uncertain)

        // A good page clears it
        #expect(await !fetcher(dir, html).load(now: now.addingTimeInterval(240)).pageChanged)
        #expect(!fetcher(dir, html).cachedOrBuiltIn(now: now.addingTimeInterval(300)).pageChanged)
    }

    @Test func fetcherWithNothingSavedUsesBuiltIn() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(await offline(dir).load(now: now).source == .builtIn)
    }

    @Test func unknownPagePartsBlockConfidence() {
        let html = page(schedule: defaultSchedule + "<h3>Holidays</h3><ul><li>Southbound only</li></ul>")
        #expect(Trust.assess(live(html), now: now).verdict == .uncertain)
    }

    @Test func brokenScheduleBlocksConfidence() {
        let bad = WeeklySchedule(
            weekday: [LaneWindow(.southbound, TimeOfDay(5), TimeOfDay(12)), LaneWindow(.northbound, TimeOfDay(11), TimeOfDay(23))],
            weekend: WeeklySchedule.builtIn.weekend
        )
        #expect(Trust.scheduleProblem(bad) != nil)
        #expect(Trust.scheduleProblem(.builtIn) == nil)
    }

    @Test func holidays() {
        #expect(Holidays.name(for: day(2026, 11, 26)) == "Thanksgiving")
        #expect(Holidays.name(for: day(2026, 11, 27)) == "Day after Thanksgiving")
        #expect(Holidays.name(for: day(2026, 5, 25)) == "Memorial Day")
        #expect(Holidays.name(for: day(2026, 9, 7)) == "Labor Day")
        // July 4, 2026 is a Saturday, observed Friday the 3rd
        #expect(Holidays.name(for: day(2026, 7, 3)) == "Independence Day")
        #expect(Holidays.name(for: day(2026, 7, 4)) == "Independence Day")
        #expect(Holidays.name(for: day(2026, 11, 18)) == nil)
    }
}
