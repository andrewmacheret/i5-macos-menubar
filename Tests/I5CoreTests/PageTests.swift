import Foundation
import Testing
@testable import I5Core

// The popover's words for real /status answers. Ported from i5-client/test/page.test.tsx.

/// Everything the popover says for a snapshot, joined up, for checking what a reader sees
func allText(_ snap: Snapshot, loaded: Bool = true) -> String {
    var parts: [String] = []
    let h = Page.header(snap, loading: !loaded)
    parts += [h.title, h.subtitle]
    if snap.check.verdict == .uncertain {
        parts += snap.check.concerns.flatMap { [$0.title, $0.detail] }
        parts.append("\(Page.liveSourcesLead) WSDOT Traffic on Bluesky · Traffic cameras · WSDOT page")
    }
    parts += Page.noticesToday(snap).flatMap { [$0.notice.title, $0.text] }
    parts += [Page.timelineTitle(snap), "Today", Page.todayDoubt(snap)?.title ?? "", Page.timelineSummary(snap.todaySegments),
              "Tomorrow", snap.tomorrowDoubts.first?.title ?? "", Page.timelineSummary(snap.tomorrowSegments)]
    if let t = Page.travelTimes(snap) {
        parts.append("Travel times Express lanes Regular lanes")
        parts += t.rows.map { r in
            "\(r.label) \(r.express)\(r.saves.map { " · saves \($0) min" } ?? "") \(r.regular)\(r.times.usual.map { " · usually \($0)" } ?? "")"
        }
        parts.append(t.hint)
    }
    if !snap.status.cameras.isEmpty { parts += ["Cameras", Cameras.summary(snap.status.cameras, open: false)] }
    parts.append("Coming up")
    let changes = Page.comingUp(snap)
    parts += changes.isEmpty ? ["No changes coming up."] : changes.map { "\($0.to.title) \(Format.when($0.at, now: snap.now))" }
    if let p = Page.planned(snap) {
        parts.append("Planned changes")
        parts += p.notices.flatMap { [$0.notice.title] + $0.times + [$0.note ?? "", $0.wordsTitle, $0.moreInfo ?? ""] }
        parts += p.holidays.flatMap { [$0.title, $0.detail] }
    }
    let r = Page.regularSchedule(snap)
    parts += ["Regular schedule", r.hint ?? ""]
    parts += ["Sources"] + Page.sources(snap).flatMap { [$0.title, $0.subtitle, $0.url] }
    parts += [Page.dataStatus(snap, loaded: loaded).text, Page.readingText(snap) ?? "", Page.liveText(snap) ?? ""]
    return parts.filter { !$0.isEmpty }.joined(separator: " ")
}

@Suite struct EveryFixtureTests {
    @Test(arguments: fixtureNames)
    func rendersEverySection(name: String) throws {
        let text = allText(try snapshot(name))
        for section in ["Today", "Tomorrow", "Coming up", "Regular schedule", "Sources", "WSDOT Traffic on Bluesky"] {
            #expect(text.contains(section))
        }
        for bad in ["nil", "Optional", "NaN", "x.com", "wsdot_traffic"] {
            #expect(!text.contains(bad))
        }
    }
}

@Suite struct PageTests {
    @Test func showsAConfirmedDirectionWhatHappensNextAndTheNoticesComingUp() throws {
        let snap = try snapshot("confident")
        let h = Page.header(snap, loading: false)
        #expect(h.title == "Northbound")
        #expect(h.subtitle.hasPrefix("Closes at 11:00 PM · "))
        #expect(h.subtitle.hasSuffix("h"))
        #expect(snap.check.verdict == .confident)
        // The alert's lane reduction starts tonight
        let today = Page.noticesToday(snap)
        #expect(today.contains { $0.notice.title == "Reduced to two lanes at night" && $0.text == "From 7:00 PM until 5:00 AM tomorrow." })
        // Planned changes from the page and the alert
        let planned = try #require(Page.planned(snap))
        let titles = planned.notices.map(\.notice.title)
        #expect(titles.contains("Weekend-long full closure"))
        #expect(planned.notices.contains { $0.note == "Start time is approximate." })
        #expect(titles.contains("Closing early at 9 p.m."))
        #expect(planned.notices.contains { $0.times.contains("Wed, Dec 2 9:00 PM → Thu, Dec 3 5:00 AM") })
        #expect(planned.notices.map(\.wordsTitle).contains("WSDOT's words"))
        #expect(planned.notices.map(\.wordsTitle).contains("WSDOT's alert"))
        let alert = "https://wsdot.com/Travel/Real-time/Map/?featureid=727762&featuretype=alert"
        #expect(planned.notices.contains { $0.moreInfo == alert })
        #expect(Page.sources(snap).contains(Page.SourceLink(title: "WSDOT highway alert", subtitle: "About the express lanes", url: alert)))
        #expect(Page.readingText(snap) == "Notices read by gemini-4-hydrogen and gpt-oss-120b.")
        #expect(Page.liveText(snap) == "WSDOT's sensors at 3:00 PM: 18 min northbound through the express lanes.")
        #expect(Page.timelineSummary(snap.todaySegments) == "Southbound 5 AM to 11 AM, Northbound 11:15 AM to 11 PM")
        #expect(Page.timelineSummary(snap.tomorrowSegments) == "Southbound 5 AM to 11 AM, Northbound 11:15 AM to 9 PM")
        #expect(Page.dataStatus(snap, loaded: true) == ("Checked WSDOT at 3:00 PM", false))
    }

    @Test func notesThatLinkToTheExpressLanesPageGetNoMoreInfo() throws {
        let planned = try #require(Page.planned(try snapshot("confident")))
        let page = planned.notices.filter { $0.notice.link == Sources.expressLanes }
        #expect(!page.isEmpty)
        #expect(page.allSatisfy { $0.moreInfo == nil })
    }

    @Test func comparesTheExpressLanesWithTheRegularLanes() throws {
        let text = allText(try snapshot("confident"))
        #expect(text.contains("Travel times Express lanes Regular lanes"))
        #expect(text.contains("Seattle → Everett 18 min · saves 8 min 26 min · usually 22"))
        #expect(text.contains("Everett → Seattle — 15 min · usually 16"))
        let t = try #require(Page.travelTimes(try snapshot("confident")))
        #expect(t.hint == "Downtown Seattle to Everett, from WSDOT's sensors at 3:00 PM. A dash means the express lanes aren't open that way.")
    }

    @Test func onlySaysSavesForTwoMinutesOrMore() throws {
        let f = try fixture("confident")
        var s = f.status
        s.live?.trips?.northbound = TripTimes(express: 25, regular: 26, usual: nil)
        let row = try #require(Page.travelTimes(Snapshot(status: s, now: f.at))?.rows.first)
        #expect(row.saves == nil)
        #expect(row.express == "25 min")
    }

    @Test func leavesOutTravelTimesFromOldReadingsWithoutThemOrOnceTheyAre30MinutesOld() throws {
        #expect(Page.travelTimes(try snapshot("holiday")) == nil)
        let f = try fixture("confident")
        #expect(Page.travelTimes(Snapshot(status: f.status, now: f.at + 30 * 60_000)) != nil)
        #expect(Page.travelTimes(Snapshot(status: f.status, now: f.at + 31 * 60_000)) == nil)
        #expect(!allText(Snapshot(status: f.status, now: f.at + 31 * 60_000)).contains("Travel times"))
        var none = f.status
        none.live?.trips = Trips(northbound: TripTimes(express: nil, regular: nil, usual: 20),
                                 southbound: TripTimes(express: nil, regular: nil, usual: 20))
        #expect(Page.travelTimes(Snapshot(status: none, now: f.at)) == nil)
    }

    @Test func cantConfirmTheDayAfterThanksgivingWithNoHolidayNotice() throws {
        let snap = try snapshot("holiday")
        let text = allText(snap)
        #expect(snap.check.verdict == .uncertain)
        #expect(snap.check.shown == nil)
        #expect(Page.header(snap, loading: false) == Page.Header(title: "Can't confirm", subtitle: "Expected northbound, but don't rely on it", tone: .warning))
        #expect(snap.check.concerns.map(\.title).contains("No word yet on Thanksgiving"))
        #expect(text.contains("Check a live source before you drive: WSDOT Traffic on Bluesky · Traffic cameras · WSDOT page"))
        #expect(Page.sources(snap).map(\.url).contains("https://bsky.app/profile/traffic.wsdot.wa.gov"))
        // No cameras from the server, so "Traffic cameras" opens the travel map
        guard case .url(let url) = Page.trafficCameras(snap.status) else { Issue.record("Expected a link"); return }
        #expect(url.hasPrefix("https://wsdot.com/Travel/Real-time/Map/?layers="))
        #expect(url == Sources.travelMap)
    }

    @Test func sendsTrafficCamerasToTheCamerasSectionWhenTheServerSentCameras() throws {
        var s = try fixture("holiday").status
        s.cameras = try fixture("confident").status.cameras
        #expect(Page.trafficCameras(s) == .section)
    }

    @Test func saysItIsCheckingWhileTheModelsReadANewPage() throws {
        let snap = try snapshot("checking")
        #expect(snap.check.verdict == .checking)
        #expect(Page.header(snap, loading: false) == Page.Header(title: "Checking…", subtitle: "Reading WSDOT's latest update", tone: .unknown))
        #expect(!allText(snap).contains("Check a live source before you drive"))
        #expect(Page.readingText(snap) == "Reading WSDOT's latest update…")
    }

    @Test func warnsWhenNoModelCouldReadTheLatestPage() throws {
        let snap = try snapshot("failed")
        #expect(Page.header(snap, loading: false).title == "Can't confirm")
        #expect(Page.readingText(snap) == "Couldn't read WSDOT's latest update, so earlier notices are shown.")
        // The earlier page lists no regular hours
        #expect(Page.regularSchedule(snap).hint?.hasPrefix("WSDOT's page doesn't list its regular schedule right now.") == true)
        #expect(Page.regularSchedule(snap).schedule == .builtIn)
        // Its unclear notice is months away, so it isn't in the next two weeks' plans
        let unclear = try #require(snap.status.published?.notices.first { $0.kind == .unclear })
        #expect(Page.certaintyText(unclear) == "Exact times unclear. The app won't confirm a direction then.")
        #expect(Page.planned(snap)?.notices.contains { $0.notice.kind == .unclear } != true)
    }

    @Test func warnsWhenWSDOTsPageHasBeenDownForHours() throws {
        let snap = try snapshot("stale")
        #expect(snap.check.verdict == .uncertain)
        #expect(snap.check.concerns.first?.title == "Data is 3h old")
        #expect(Page.dataStatus(snap, loaded: true) == ("WSDOT didn't answer at 2:50 PM. Using what it said at 12:00 PM.", true))
    }

    @Test func showsANoticeInEffectNowAndThatItCouldLastLonger() throws {
        let snap = try snapshot("winter-2022")
        #expect(Page.header(snap, loading: false).title == "Southbound")
        #expect(allText(snap).contains("Southbound for winter weather Now until 11:00 AM Mon. It could last longer."))
    }

    @Test func handlesANoticeThatRunsPastTheEndOfTheTimeline() throws {
        let snap = try snapshot("revive-2026")
        let text = allText(snap)
        #expect(Page.header(snap, loading: false).title == "Northbound")
        #expect(Page.header(snap, loading: false).subtitle == "No changes before Fri, Oct 9")
        #expect(text.contains("Northbound around the clock for Revive I-5 Now until 12:00 AM Fri, Jan 1. It could last longer."))
        #expect(text.contains("Ninth Avenue on-ramp closed Now until 12:00 AM Tue, Sep 8."))
        #expect(Page.comingUp(snap).isEmpty)
        #expect(text.contains("No changes coming up."))
    }

    @Test func listsUpTo20TimesPerNoticeAndFoldsTheRestBehindDots() throws {
        let f = try fixture("confident")
        var s = f.status
        var n = try #require(s.published?.notices.first { $0.title == "Closing early at 9 p.m." })
        let day = 86_400_000
        n.spans = (1...25).map { i in Span(start: f.at + i * day, end: f.at + i * day + 3_600_000) }
        s.published?.notices = [n]
        let item = try #require(Page.planned(Snapshot(status: s, now: f.at))?.notices.first)
        #expect(item.times.count == 25)
        #expect(item.shownTimes.count == 20)
        #expect(item.shownTimes.allSatisfy { $0.contains("→") })
        #expect(item.moreTimes.count == 5)
        #expect(item.moreLabel == "Show 5 more times")
        #expect(item.shownTimes + item.moreTimes == item.times)
    }

    @Test func doesNotFoldTwentyTimesOrFewer() throws {
        let planned = try #require(Page.planned(try snapshot("confident")))
        #expect(planned.notices.allSatisfy { $0.times.count <= 20 && $0.moreLabel == nil })
    }

    @Test func listsHolidaysWithNoNoticeInPlannedChanges() throws {
        let planned = try #require(Page.planned(try snapshot("holiday")))
        #expect(planned.holidays.map(\.title) == ["No word yet on Thanksgiving"])
    }

    @Test func saysItIsLoadingBeforeTheFirstAnswer() {
        let snap = Snapshot(status: .empty, now: t("2026-12-01T12:00"), refreshing: true)
        #expect(Page.header(snap, loading: true) == Page.Header(title: "Loading…", subtitle: "Asking the server", tone: .unknown))
        #expect(snap.check.verdict == .checking)
        #expect(!allText(snap, loaded: false).contains("Can't confirm"))
        #expect(Page.dataStatus(snap, loaded: false).text == "Loading…")
    }

    @Test func saysItCantReachTheServerWhenNothingIsSaved() {
        let snap = Snapshot(status: .empty, now: t("2026-12-01T12:00"))
        #expect(snap.check.verdict == .uncertain)
        #expect(Page.header(snap, loading: true, loadError: "Couldn't reach the server: offline").title == "Can't reach the server")
    }
}

@Suite struct CameraTests {
    let f: Fixture
    var cameras: [Camera] { f.status.cameras }

    init() throws { f = try fixture("confident") }

    @Test func startClosedOfferingTheExpressLaneOnes() {
        #expect(Cameras.summary(cameras, open: false) == "Show 2 express lane cameras, downtown to Northgate")
        #expect(Cameras.summary(cameras, open: true) == "Hide 2 express lane cameras, downtown to Northgate")
    }

    @Test func areLeftOutWhenTheServerDidNotSendAny() throws {
        let snap = try snapshot("holiday")
        #expect(snap.status.cameras.isEmpty)
        #expect(!allText(snap).contains("Cameras"))
    }

    @Test func showExpressLaneCamerasFirstThenAllOfThemSouthToNorth() {
        #expect(Cameras.shown(cameras, all: false).map(\.name) == ["Roanoke St Express Lanes", "Ship Canal Express Lanes"])
        #expect(Cameras.shown(cameras, all: true).map(\.name) == ["Yesler Way", "Roanoke St Express Lanes", "Ship Canal Express Lanes", "NE 45th St"])
        #expect(Cameras.toggleText(cameras, all: false) == "Show all 4 cameras along I-5")
        #expect(Cameras.toggleText(cameras, all: true) == "Only express lane cameras")
        // With no express lane cameras, show them all and offer no toggle
        let plain = cameras.filter { !$0.express }
        #expect(Cameras.shown(plain, all: false) == plain)
        #expect(Cameras.summary(plain, open: false) == "Show 2 cameras, downtown to Northgate")
        #expect(Cameras.toggleText(plain, all: false) == nil)
        #expect(Cameras.toggleText(Cameras.express(cameras), all: false) == nil)
    }

    @Test func showWSDOTsPictureWhichChangesAddressEvery5MinutesWithItsMilepost() throws {
        let c = cameras[1]
        let url = Cameras.imageURL(c, now: f.at)
        #expect(url.range(of: #"^https://images\.wsdot\.wa\.gov/nw/\w+\.jpg\?v=\d+$"#, options: .regularExpression) != nil)
        #expect(c.name == "Roanoke St Express Lanes")
        #expect(Cameras.milepost(c) == "MP 168")
        #expect(Cameras.milepost(cameras[2]) == "MP 168.8")
        #expect(Cameras.imageURL(c, now: f.at + 60_000) == url)
        #expect(Cameras.imageURL(c, now: f.at + 5 * 60_000) != url)
    }

    @Test func addTheReloadCountToThePictureAddressAfterTheFirstTry() {
        let c = cameras[1]
        let v = Cameras.version(f.at)
        #expect(v == f.at / (5 * 60_000))
        #expect(Cameras.imageURL(c, now: f.at, reload: 0) == "\(c.image)?v=\(v)")
        #expect(Cameras.imageURL(c, now: f.at, reload: 1) == "\(c.image)?v=\(v)-1")
        #expect(Cameras.imageURL(c, now: f.at, reload: 3) == "\(c.image)?v=\(v)-3")
        #expect(Cameras.imageURL(c, now: f.at + 5 * 60_000, reload: 3) == "\(c.image)?v=\(v + 1)-3")
    }

    @Test func retryAFailedPicture3TimesAfter5_15And45Seconds() {
        #expect(Cameras.retryDelay(afterFailures: 0) == nil)
        #expect(Cameras.retryDelay(afterFailures: 1) == 5_000)
        #expect(Cameras.retryDelay(afterFailures: 2) == 15_000)
        #expect(Cameras.retryDelay(afterFailures: 3) == 45_000)
        #expect(Cameras.retryDelay(afterFailures: 4) == nil)
    }

    @Test func useTheSameWordsAsTheWebPage() {
        #expect(Cameras.failed == "Picture didn't load")
        #expect(Cameras.reloadHelp == "Reload picture")
        #expect(Cameras.reloadLabel(cameras[1]) == "Reload the picture from Roanoke St Express Lanes")
        #expect(Cameras.openInBrowser == "Open in browser")
        #expect(Cameras.travelMapLink == "All cameras on WSDOT's travel map")
    }

    @Test func giveTheExpandedCameraARowToItself() {
        let names = { (rows: [[Camera]]) in rows.map { $0.map(\.name) } }
        #expect(names(Cameras.rows(cameras, expanded: nil)) == [["Yesler Way", "Roanoke St Express Lanes"], ["Ship Canal Express Lanes", "NE 45th St"]])
        #expect(names(Cameras.rows(cameras, expanded: cameras[0].id)) == [["Yesler Way"], ["Roanoke St Express Lanes", "Ship Canal Express Lanes"], ["NE 45th St"]])
        #expect(names(Cameras.rows(cameras, expanded: cameras[1].id)) == [["Yesler Way"], ["Roanoke St Express Lanes"], ["Ship Canal Express Lanes", "NE 45th St"]])
        #expect(names(Cameras.rows(cameras, expanded: cameras[3].id)) == [["Yesler Way", "Roanoke St Express Lanes"], ["Ship Canal Express Lanes"], ["NE 45th St"]])
        // A camera that isn't shown, like after switching back to express lanes only
        #expect(names(Cameras.rows(Cameras.express(cameras), expanded: cameras[0].id)) == [["Roanoke St Express Lanes", "Ship Canal Express Lanes"]])
    }

    @Test func linkToTheTravelMapZoomedInOnTheCamera() throws {
        let c = cameras[0]
        let url = try #require(URLComponents(string: Cameras.mapLink(c)))
        #expect("\(url.scheme!)://\(url.host!)\(url.path)" == "https://wsdot.com/Travel/Real-time/Map/")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["layers"] == "traffic-flow,alert,camera")
        #expect(query["base"] == "wsdot")
        let box = try #require(query["extent"]).split(separator: ",").map { Double($0)! }
        #expect(box[0] < c.lon && box[2] > c.lon)
        #expect(box[1] < c.lat && box[3] > c.lat)
        #expect(abs((box[2] - box[0]) - 0.012) < 0.00001)
        // The same address the web page builds
        #expect(Cameras.mapLink(c) == "https://wsdot.com/Travel/Real-time/Map/?layers=traffic-flow%2Calert%2Ccamera&base=wsdot&extent=-122.33089%2C47.59770%2C-122.31889%2C47.60570&fromLink=true")
    }
}
