/// Normalized usage cache. Mac counterpart of `cache.py`.
///
/// Fixes two issues called out in the Mac handoff: startup cache is
/// immediately marked stale (it can never masquerade as freshly fetched
/// data), and writes are atomic so overlapping saves cannot corrupt the file.
import Foundation

public final class UsageCache: Sendable {
    public let path: URL

    public init(path: URL? = nil) {
        self.path = path ?? Self.defaultPath()
    }

    public static func defaultPath() -> URL {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("AIUsageMonitor/cache.json")
    }

    public func load() -> [String: ProviderUsage] {
        guard let data = FileManager.default.contents(atPath: path.path) else {
            return [:]
        }
        guard let raw = (try? JSONDecoder.withISODates().decode(CacheFile.self, from: data)) else {
            return [:]
        }
        var values: [String: ProviderUsage] = [:]
        for (key, usage) in raw.providers {
            values[key] = usage.markingStale(status: .stale, error: "Cached data; not refreshed yet.")
        }
        return values
    }

    public func save(_ values: [String: ProviderUsage]) {
        let file = CacheFile(savedAt: Date(), providers: values)
        guard let data = try? JSONEncoder.withISODates().encode(file) else {
            return
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = path.deletingLastPathComponent()
                .appendingPathComponent(".cache-\(UUID().uuidString).tmp")
            try data.write(to: temporary)
            if fileManager.fileExists(atPath: path.path) {
                _ = try fileManager.replaceItemAt(path, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: path)
            }
        } catch {
            // Cache writes are best-effort; the app still holds live values.
        }
    }

    struct CacheFile: Codable {
        let savedAt: Date
        let providers: [String: ProviderUsage]
    }
}
