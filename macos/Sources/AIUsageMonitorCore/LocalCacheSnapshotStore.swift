import Foundation

/// Snapshot channel for local, unprovisioned builds: the host app writes the
/// snapshot JSON next to its own cache, where any unsandboxed process —
/// including an ad-hoc-signed widget extension whose sandbox entitlement is
/// not enforced — can read it as a plain file.
///
/// The path resolves through the process home directory, so it degrades
/// safely: a sandboxed widget (provisioned or development-signed builds)
/// sees its own container instead of the real home, finds no file, and
/// falls through to the next channel. The file holds only usage
/// percentages and reset times — never credentials.
public enum LocalCacheSnapshotStore {
    public static let fileName = "usage-snapshot.json"
    public static let directoryName = "AIUsageMonitor"

    /// The snapshot path under the writing/reading process's home.
    public static func path() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(directoryName)/\(fileName)")
    }

    /// Publishes the latest snapshot from the unsandboxed host app.
    public static func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let data = try? JSONEncoder.withISODates().encode(snapshot) else {
            return false
        }
        let url = path()
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// Loads the snapshot written by the host app. Returns nil when this
    /// process is sandboxed (its home is not the real user home) or when the
    /// file does not exist.
    public static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: path()) else { return nil }
        return try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
    }
}
