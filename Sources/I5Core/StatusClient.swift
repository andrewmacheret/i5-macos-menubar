import Foundation

public struct LoadResult: Sendable {
    /// The server's answer, or nil when it couldn't be reached or read
    public var status: ServerStatus?
    public var error: String?
}

/// Downloads GET /status from the I-5 server and keeps the last good copy on disk.
public struct StatusClient: Sendable {
    /// Where the last good copy goes. Nil keeps nothing, like the terminal tool.
    public var cacheDir: URL?
    private let download: @Sendable () async throws -> Data

    public init(cacheDir: URL? = StatusClient.defaultCacheDir, userAgent: String,
                download: (@Sendable () async throws -> Data)? = nil) {
        self.cacheDir = cacheDir
        self.download = download ?? { try await StatusClient.httpGet(userAgent: userAgent) }
    }

    public static var defaultCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.andrewmacheret.i5", isDirectory: true)
    }

    private var savedFile: URL? { cacheDir?.appendingPathComponent("status.json") }

    /// Downloads a fresh copy. Only a copy that reads correctly replaces the saved one.
    public func load() async -> LoadResult {
        let data: Data
        do {
            data = try await download()
        } catch {
            return LoadResult(status: nil, error: "Couldn't reach the server: \(error.localizedDescription)")
        }
        guard let status = try? StatusClient.decode(data) else {
            return LoadResult(status: nil, error: "The server sent something the app can't read")
        }
        if let cacheDir, let savedFile {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? data.write(to: savedFile, options: .atomic)
        }
        return LoadResult(status: status, error: nil)
    }

    /// The last good copy, so the app has something to show right away
    public func saved() -> ServerStatus? {
        guard let cacheDir, let savedFile else { return nil }
        // Versions before the server saved WSDOT's page here instead
        for old in ["express-lanes.html", "page-problem.txt"] {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(old))
        }
        guard let data = try? Data(contentsOf: savedFile) else { return nil }
        return try? StatusClient.decode(data)
    }

    /// Reads a /status answer. It has to be an object with a "published" field, even a null one,
    /// so an error page never replaces a good copy.
    public static func decode(_ data: Data) throws -> ServerStatus {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object.keys.contains("published") else {
            throw LoadError(message: "Not a status")
        }
        return try JSONDecoder().decode(ServerStatus.self, from: data)
    }

    public static func httpGet(userAgent: String) async throws -> Data {
        var req = URLRequest(url: URL(string: Sources.status)!, timeoutInterval: 20)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw LoadError(message: "The server returned HTTP \(http.statusCode)")
        }
        return body
    }
}

struct LoadError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
