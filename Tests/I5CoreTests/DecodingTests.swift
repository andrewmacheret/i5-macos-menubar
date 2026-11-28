import Foundation
import Testing
@testable import I5Core

@Suite struct DecodingTests {
    @Test(arguments: fixtureNames)
    func readsEveryFixture(name: String) throws {
        // The fixtures carry fields the app doesn't use, like "current" and "about"
        let s = try StatusClient.decode(try JSONSerialization.data(withJSONObject: try #require(
            JSONSerialization.jsonObject(with: try fixtureData(name)) as? [String: Any])["status"]!))
        let p = try #require(s.published)
        #expect(!p.segments.isEmpty)
        #expect(p.horizon.start < p.horizon.end)
        #expect(s.fetchedAt != nil)
    }

    @Test func readsTheConfidentFixtureFully() throws {
        let s = try fixture("confident").status
        let p = try #require(s.published)
        #expect(p.segments.count == 241)
        #expect(p.schedule?.weekday.first == LaneWindow(status: .southbound, start: hm(5), end: hm(11)))
        #expect(p.notices.count == 4)
        #expect(p.notices[0].startCertainty == .approximate)
        #expect(p.notices[2].source == .alert)
        #expect(p.page?.models == ["gemini-4-hydrogen", "gpt-oss-120b"])
        #expect(p.alerts.count == 1)
        #expect(s.live?.trips?.southbound.express == nil)
        #expect(s.live?.trips?.northbound.usual == 22)
        #expect(s.cameras.count == 4)
        #expect(s.cameras[2].milepost == 168.8)
    }

    @Test func toleratesMissingFields() throws {
        let s = try StatusClient.decode(Data(#"{"published": null}"#.utf8))
        #expect(s == .empty)
        let older = try StatusClient.decode(Data("""
        {"published": {"horizon": {"start": 0, "end": 10}, "segments": [{"start": 0, "end": 10, "status": "closed"}],
          "notices": [{"title": "A notice"}], "doubts": [{"start": 0, "end": 5}]},
         "fetchedAt": 1, "live": {"at": 1, "northbound": 18, "southbound": null}}
        """.utf8))
        let p = try #require(older.published)
        #expect(p.notices.first?.spans == [])
        #expect(p.notices.first?.kind == .other)
        #expect(p.doubts.first?.checking == false)
        #expect(p.page == nil && p.schedule == nil && p.alerts.isEmpty)
        #expect(older.live?.trips == nil)
        #expect(older.cameras.isEmpty)
        #expect(older.checkedAt == nil && older.error == nil)
    }

    @Test func toleratesNewValuesAndNumbers() throws {
        let s = try StatusClient.decode(Data("""
        {"published": {"horizon": {"start": 0, "end": 10.0}, "segments": [{"start": 0, "end": 10, "status": "sideways"}],
          "doubts": [{"start": 0, "end": 5, "title": "x", "source": "satellite", "checking": true, "extra": [1, 2]}],
          "notices": [{"title": "n", "kind": "reversible", "startCertainty": "maybe", "source": "radio"}]},
         "fetchedAt": 1.0, "error": null, "newThing": {"a": 1},
         "cameras": [{"id": 1, "name": "A", "milepost": 165, "express": true, "lat": 47.6, "lon": -122.3, "image": "https://x/a.jpg"},
                     {"id": 2, "name": "No picture", "lat": 47.6, "lon": -122.3},
                     {"id": 3, "name": "C", "milepost": 166, "express": false, "lat": 47.7, "lon": -122.3, "image": "https://x/c.jpg"}]}
        """.utf8))
        let p = try #require(s.published)
        #expect(p.horizon.end == 10)
        #expect(p.segments.first?.status == .unknown)
        #expect(p.doubts.first?.source == .other)
        #expect(p.doubts.first?.checking == true)
        #expect(p.notices.first?.kind == .other)
        #expect(p.notices.first?.startCertainty == .unknown)
        #expect(s.fetchedAt == 1)
        // A camera with no picture is left out, the others stay
        #expect(s.cameras.map(\.id) == [1, 3])
    }

    @Test func rejectsAnythingThatIsNotAStatus() {
        #expect(throws: (any Error).self) { try StatusClient.decode(Data(#"{"message": "Internal server error"}"#.utf8)) }
        #expect(throws: (any Error).self) { try StatusClient.decode(Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try StatusClient.decode(Data("<html>".utf8)) }
        // A broken doubt fails the whole answer, so the app keeps its last good copy instead of trusting less
        #expect(throws: (any Error).self) {
            try StatusClient.decode(Data(#"{"published": {"horizon": {"start": 0, "end": 1}, "doubts": [{"title": "no times"}]}}"#.utf8))
        }
    }
}

@Suite struct StatusClientTests {
    struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("i5-\(UUID().uuidString)", isDirectory: true)
    }

    func client(_ dir: URL?, _ body: @escaping @Sendable () throws -> Data) -> StatusClient {
        StatusClient(cacheDir: dir, userAgent: "test") { try body() }
    }

    func statusData(_ name: String) throws -> Data {
        let object = try #require(JSONSerialization.jsonObject(with: try fixtureData(name)) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: object["status"]!)
    }

    @Test func keepsTheLastGoodCopy() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try statusData("confident")
        let first = await client(dir) { good }.load()
        #expect(first.error == nil)
        #expect(first.status == (try fixture("confident").status))
        #expect(client(dir) { throw Offline() }.saved() == first.status)

        // The network fails, so the saved copy stays
        let down = await client(dir) { throw Offline() }.load()
        #expect(down.status == nil)
        #expect(down.error == "Couldn't reach the server: The Internet connection appears to be offline.")
        #expect(client(dir) { Data() }.saved() == first.status)

        // An error page never replaces it
        let bad = await client(dir) { Data(#"{"message": "Internal server error"}"#.utf8) }.load()
        #expect(bad.status == nil)
        #expect(bad.error == "The server sent something the app can't read")
        #expect(client(dir) { Data() }.saved() == first.status)

        // A new good answer does
        let newer = try statusData("holiday")
        _ = await client(dir) { newer }.load()
        #expect(client(dir) { Data() }.saved() == (try fixture("holiday").status))
    }

    @Test func clearsOutTheOldSavedWSDOTPage() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("express-lanes.html")
        try Data("<html>".utf8).write(to: old)
        #expect(client(dir) { Data() }.saved() == nil)
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func savesNothingWithoutAFolder() async throws {
        let good = try statusData("confident")
        let c = client(nil) { good }
        #expect(await c.load().status != nil)
        #expect(c.saved() == nil)
    }
}
