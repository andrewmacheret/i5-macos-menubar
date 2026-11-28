import Foundation

/// WSDOT's cameras along the express lanes, like the web page's Cameras section.
/// Pictures come straight from WSDOT's image server, and only once the section is opened.
public enum Cameras {
    /// WSDOT updates each picture about this often
    public static let refreshEvery = 5 * 60_000
    static let map = "https://wsdot.com/Travel/Real-time/Map/"
    public static let hint = "From WSDOT. Each picture updates about every 5 minutes."
    /// Under the hint, linking to Sources.travelMap
    public static let travelMapLink = "All cameras on WSDOT's travel map"
    public static let failed = "Picture didn't load"
    public static let reloadHelp = "Reload picture"
    public static let openInBrowser = "Open in browser"

    /// "Reload the picture from Roanoke St Express Lanes", for VoiceOver
    public static func reloadLabel(_ c: Camera) -> String { "Reload the picture from \(c.name)" }

    /// How long to wait before trying a picture again, after it failed this many times. Nil means give up.
    public static func retryDelay(afterFailures n: Int) -> Int? {
        let delays = [5_000, 15_000, 45_000]
        return n >= 1 && n <= delays.count ? delays[n - 1] : nil
    }

    /// WSDOT's travel map zoomed in on one camera, with cameras on. Its own camera links don't work.
    public static func mapLink(_ c: Camera) -> String {
        let extent = [c.lon - 0.006, c.lat - 0.004, c.lon + 0.006, c.lat + 0.004]
            .map { String(format: "%.5f", $0) }
            .joined(separator: "%2C")
        return "\(map)?layers=traffic-flow%2Calert%2Ccamera&base=wsdot&extent=\(extent)&fromLink=true"
    }

    /// Goes up by one every 5 minutes
    public static func version(_ now: Moment) -> Int { floorDiv(now, refreshEvery) }

    /// The picture's address, which changes every 5 minutes so a fresh one gets fetched.
    /// `reload` counts retries and reload clicks, so each one skips the cache too.
    public static func imageURL(_ c: Camera, now: Moment, reload: Int = 0) -> String {
        "\(c.image)?v=\(version(now))\(reload > 0 ? "-\(reload)" : "")"
    }

    /// Two pictures per row, except the expanded one, which gets a row to itself
    public static func rows(_ cameras: [Camera], expanded: Int?) -> [[Camera]] {
        var rows: [[Camera]] = []
        var pair: [Camera] = []
        for c in cameras {
            if c.id == expanded {
                if !pair.isEmpty { rows.append(pair) }
                rows.append([c])
                pair = []
            } else {
                pair.append(c)
                if pair.count == 2 {
                    rows.append(pair)
                    pair = []
                }
            }
        }
        if !pair.isEmpty { rows.append(pair) }
        return rows
    }

    public static func express(_ cameras: [Camera]) -> [Camera] { cameras.filter(\.express) }

    /// Express lane cameras, or all of them once asked or when none look at the express lanes
    public static func shown(_ cameras: [Camera], all: Bool) -> [Camera] {
        let express = express(cameras)
        return all || express.isEmpty ? cameras : express
    }

    /// "Show 2 express lane cameras, downtown to Northgate"
    public static func summary(_ cameras: [Camera], open: Bool) -> String {
        let express = express(cameras).count
        let what = express > 0 ? "\(express) express lane cameras" : "\(cameras.count) cameras"
        return "\(open ? "Hide" : "Show") \(what), downtown to Northgate"
    }

    /// The button under the pictures, or nil when there's nothing to switch between
    public static func toggleText(_ cameras: [Camera], all: Bool) -> String? {
        let express = express(cameras).count
        guard express > 0, express < cameras.count else { return nil }
        return all ? "Only express lane cameras" : "Show all \(cameras.count) cameras along I-5"
    }

    /// "MP 168" or "MP 168.8"
    public static func milepost(_ c: Camera) -> String {
        let m = c.milepost
        return m == m.rounded() && abs(m) < 1e15 ? "MP \(Int(m))" : "MP \(m)"
    }
}
