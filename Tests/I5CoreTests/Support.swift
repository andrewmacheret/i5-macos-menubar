import Foundation
import Testing
@testable import I5Core

// Shared helpers. The fixtures are real /status answers copied from i5-client/test/fixtures,
// made by i5-server-lambdas from saved copies of WSDOT's page. Each has the moment it describes.

struct Fixture: Decodable {
    var about: String
    var at: Moment
    var status: ServerStatus
}

let fixtureNames = ["checking", "confident", "failed", "holiday", "revive-2026", "stale", "winter-2022"]

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
    return try Data(contentsOf: url)
}

func fixture(_ name: String) throws -> Fixture {
    try JSONDecoder().decode(Fixture.self, from: try fixtureData(name))
}

func snapshot(_ name: String) throws -> Snapshot {
    let f = try fixture(name)
    return Snapshot(status: f.status, now: f.at)
}

/// A Seattle time like "2026-11-18T08:00"
func t(_ s: String) -> Moment {
    let parts = s.split(separator: "T")
    let clock = parts[1].split(separator: ":").map { Int($0)! }
    return Seattle.instant(String(parts[0]), clock[0] * 60 + clock[1])
}

func seg(_ start: String, _ end: String, _ status: LaneStatus) -> Segment {
    Segment(start: t(start), end: t(end), status: status)
}

/// A small published timeline around Wed, Nov 18, 2026
func timeline(doubts: [Doubt] = [], horizon: Horizon? = nil, segments: [Segment]? = nil) -> Timeline {
    Timeline(
        publishedAt: t("2026-11-18T08:00"),
        horizon: horizon ?? Horizon(start: t("2026-11-17T00:00"), end: t("2026-11-20T00:00")),
        schedule: nil,
        segments: segments ?? [
            seg("2026-11-17T00:00", "2026-11-17T05:00", .closed),
            seg("2026-11-17T05:00", "2026-11-17T11:00", .southbound),
            seg("2026-11-17T11:00", "2026-11-17T11:15", .closed),
            seg("2026-11-17T11:15", "2026-11-17T23:00", .northbound),
            seg("2026-11-17T23:00", "2026-11-18T05:00", .closed),
            seg("2026-11-18T05:00", "2026-11-18T11:00", .southbound),
            seg("2026-11-18T11:00", "2026-11-18T11:15", .closed),
            seg("2026-11-18T11:15", "2026-11-18T21:00", .northbound),
            seg("2026-11-18T21:00", "2026-11-19T05:00", .closed),
            seg("2026-11-19T05:00", "2026-11-20T00:00", .southbound),
        ],
        doubts: doubts,
        notices: [],
        page: DocumentInfo(kind: "page", hash: "abc", firstSeen: t("2026-11-18T07:00"), models: ["m"], status: .answered, link: nil),
        alerts: []
    )
}

/// Fresh data read 5 minutes before `now`
func status(_ now: Moment, published: Timeline? = timeline(), fetchedAt: Moment? = nil, error: String? = nil,
            live: LiveReading? = nil) -> ServerStatus {
    ServerStatus(published: published, fetchedAt: fetchedAt ?? now - 5 * 60_000, checkedAt: now - 5 * 60_000,
                 error: error, live: live)
}

func doubt(_ start: String, _ end: String, title: String = "A doubt", source: SourceKind = .page, checking: Bool = false) -> Doubt {
    Doubt(start: t(start), end: t(end), title: title, detail: "Why", link: nil, source: source, checking: checking)
}
