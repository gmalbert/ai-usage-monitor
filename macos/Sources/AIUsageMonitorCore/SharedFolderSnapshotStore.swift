import Foundation

/// Snapshot channel for local builds without a provisioning profile: the
/// host app writes the snapshot JSON into `/Users/Shared`, and the sandboxed
/// widget extension reads it through the read-only temporary sandbox
/// exception declared in its entitlements.
///
/// The app's own cache directory cannot be used here: a sandboxed widget
/// resolves `homeDirectoryForCurrentUser` to its own container, so a file in
/// the real user home is invisible to it. The App Group container and
/// loopback HTTP channels are also unavailable to ad-hoc builds — container
/// manager denies the App Group write without a team identity, and the
/// widget's sandbox profile drops network access. `/Users/Shared` is the one
/// location both processes can reach. The file holds only usage percentages
/// and reset times — never credentials.
public enum SharedFolderSnapshotStore {
    public static let directory = URL(fileURLWithPath: "/Users/Shared/AIUsageMonitor", isDirectory: true)
    public static let fileName = "usage-snapshot.json"

    public static var defaultURL: URL {
        directory.appendingPathComponent(fileName)
    }

    /// Publishes the latest snapshot from the unsandboxed host app.
    public static func save(_ snapshot: UsageSnapshot, to url: URL = defaultURL) -> Bool {
        guard let data = try? JSONEncoder.withISODates().encode(snapshot) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// Loads the snapshot written by the host app. Returns nil when the file
    /// does not exist or the sandbox exception does not cover it.
    public static func load(from url: URL = defaultURL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
    }
}
