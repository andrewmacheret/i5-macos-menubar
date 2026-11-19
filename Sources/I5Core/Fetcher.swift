import Foundation

public enum DataSource: Equatable, Sendable {
    /// Freshly read from WSDOT
    case live(Date)
    /// Using the last good copy, saved at this time
    case cached(Date)
    /// Nothing good saved, using the schedule baked into the app
    case builtIn
}

public struct FetchResult: Sendable {
    public var info: ExpressLanesInfo
    public var source: DataSource
    public var error: String?
    /// WSDOT's page loaded but couldn't be read
    public var pageChanged = false

    public init(info: ExpressLanesInfo, source: DataSource, error: String? = nil, pageChanged: Bool = false) {
        self.info = info
        self.source = source
        self.error = error
        self.pageChanged = pageChanged
    }
}

/// Downloads the WSDOT page and keeps the last good copy on disk.
public struct Fetcher: Sendable {
    public var cacheDir: URL

    public init(cacheDir: URL = Fetcher.defaultCacheDir) {
        self.cacheDir = cacheDir
    }

    public static var defaultCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.andrewmacheret.i5", isDirectory: true)
    }

    private var pageFile: URL { cacheDir.appendingPathComponent("express-lanes.html") }

    public func load(now: Date = Date()) async -> FetchResult {
        let data: Data
        do {
            var req = URLRequest(url: Sources.expressLanes, timeoutInterval: 20)
            req.setValue("Mozilla/5.0 (Macintosh) I5Express", forHTTPHeaderField: "User-Agent")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (body, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                return cachedOrBuiltIn(now: now, error: "WSDOT returned HTTP \(http.statusCode)")
            }
            data = body
        } catch {
            return cachedOrBuiltIn(now: now, error: error.localizedDescription)
        }

        let info = Parser.parse(html: String(decoding: data, as: UTF8.self), now: now)
        guard info.scheduleFromPage else {
            // Don't overwrite the last good copy with a page we can't read
            var fallback = cachedOrBuiltIn(now: now, error: "Couldn't read WSDOT's page")
            fallback.pageChanged = true
            fallback.info.warnings += info.warnings
            return fallback
        }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: pageFile, options: .atomic)
        return FetchResult(info: info, source: .live(now), error: nil)
    }

    public func cachedOrBuiltIn(now: Date = Date(), error: String? = nil) -> FetchResult {
        if let data = try? Data(contentsOf: pageFile),
           let attrs = try? FileManager.default.attributesOfItem(atPath: pageFile.path),
           let modified = attrs[.modificationDate] as? Date {
            let info = Parser.parse(html: String(decoding: data, as: UTF8.self), now: now)
            if info.scheduleFromPage {
                return FetchResult(info: info, source: .cached(modified), error: error)
            }
        }
        return FetchResult(info: .builtIn, source: .builtIn, error: error)
    }
}
