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
    private let download: @Sendable () async throws -> Data

    public init(cacheDir: URL = Fetcher.defaultCacheDir, download: @escaping @Sendable () async throws -> Data = Fetcher.httpGet) {
        self.cacheDir = cacheDir
        self.download = download
    }

    public static var defaultCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.andrewmacheret.i5", isDirectory: true)
    }

    private var pageFile: URL { cacheDir.appendingPathComponent("express-lanes.html") }

    // Remembers that the newest page couldn't be read, until a good one comes in.
    // Without it a restart or a failed download would quietly trust the old copy again.
    private var problemFile: URL { cacheDir.appendingPathComponent("page-problem.txt") }

    public func load(now: Date = Date()) async -> FetchResult {
        let data: Data
        do {
            data = try await download()
        } catch {
            return cachedOrBuiltIn(now: now, error: error.localizedDescription)
        }

        let info = Parser.parse(html: String(decoding: data, as: UTF8.self), now: now)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        guard info.scheduleFromPage else {
            // Don't overwrite the last good copy with a page we can't read
            try? info.warnings.joined(separator: "\n").write(to: problemFile, atomically: true, encoding: .utf8)
            var fallback = cachedOrBuiltIn(now: now, error: "Couldn't read WSDOT's page")
            if !fallback.pageChanged {
                fallback.pageChanged = true
                fallback.info.warnings += info.warnings
            }
            return fallback
        }
        try? data.write(to: pageFile, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: pageFile.path)
        try? FileManager.default.removeItem(at: problemFile)
        return FetchResult(info: info, source: .live(now), error: nil)
    }

    public func cachedOrBuiltIn(now: Date = Date(), error: String? = nil) -> FetchResult {
        var result = FetchResult(info: .builtIn, source: .builtIn, error: error)
        if let data = try? Data(contentsOf: pageFile),
           let attrs = try? FileManager.default.attributesOfItem(atPath: pageFile.path),
           let modified = attrs[.modificationDate] as? Date {
            let info = Parser.parse(html: String(decoding: data, as: UTF8.self), now: now)
            if info.scheduleFromPage {
                result = FetchResult(info: info, source: .cached(modified), error: error)
            }
        }
        if let problems = try? String(contentsOf: problemFile, encoding: .utf8) {
            result.pageChanged = true
            result.info.warnings += problems.split(separator: "\n").map(String.init)
        }
        return result
    }

    public static let httpGet: @Sendable () async throws -> Data = {
        var req = URLRequest(url: Sources.expressLanes, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh) I5Express", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError(message: "WSDOT returned HTTP \(http.statusCode)")
        }
        return body
    }
}

struct FetchError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
