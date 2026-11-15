import Foundation

/// Minimal rotating file log under `~/Library/Logs/AIUsageMonitor/`.
/// Never logs credentials or provider response bodies.
final class RotatingFileLog: @unchecked Sendable {
    static let shared = RotatingFileLog()

    let directory: URL
    private let fileName = "app.log"
    private let maximumBytes = 1_000_000
    private let backupCount = 2
    private let lock = NSLock()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let logsRoot = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            self.directory = logsRoot.appendingPathComponent("Logs/AIUsageMonitor")
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func info(_ message: String) { append("INFO", message) }
    func warn(_ message: String) { append("WARN", message) }

    private func append(_ level: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let line = "\(formatter.string(from: Date())) \(level) \(message)\n"
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
        }
        try? data.write(to: fileURL)
    }

    private func rotateIfNeeded() {
        let fileManager = FileManager.default
        guard let size = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]) as? Int,
              size > maximumBytes else {
            return
        }
        var shift = backupCount
        while shift > 0 {
            let from = directory.appendingPathComponent(shift == 1 ? fileName : "\(fileName).\(shift - 1)")
            let to = directory.appendingPathComponent("\(fileName).\(shift)")
            try? fileManager.removeItem(at: to)
            if fileManager.fileExists(atPath: from.path) {
                try? fileManager.moveItem(at: from, to: to)
            }
            shift -= 1
        }
    }
}
