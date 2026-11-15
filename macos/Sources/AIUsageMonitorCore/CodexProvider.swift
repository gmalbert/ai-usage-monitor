/// Codex adapter. Port of `providers/codex.py`.
///
/// Runs `codex app-server --stdio` for live limits and falls back to the most
/// recent local session record (marked stale) when live access fails. It never
/// reads OAuth credentials. The app-server session is a single owned process
/// with one line reader; requests time out independently and responses are
/// matched by id, ignoring interleaved notifications.
import Foundation

public struct CodexNotInstalledError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String = "Codex is not installed or not on PATH") {
        self.description = description
    }
}

public struct AppServerTimeoutError: Error, Sendable {
    public init() {}
}

public final class CodexProvider: UsageProvider {
    public let key = "codex"
    public var displayName: String { "Codex" }

    private let executableURL: URL?
    private let homeDirectory: URL

    public init(
        executableURL: URL? = nil,
        homeDirectory: URL? = nil
    ) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        if let executableURL {
            self.executableURL = executableURL
        } else {
            self.executableURL = Self.locateExecutable(homeDirectory: self.homeDirectory)
        }
    }

    // MARK: - Executable discovery

    /// Finds Codex on PATH, in common installation directories (a Finder-
    /// launched app does not inherit the user's shell PATH), and inside the
    /// Codex desktop app bundle. The bundle layout is verified against
    /// Codex 0.169 at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.
    public static func locateExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsRoots: [String]? = nil
    ) -> URL? {
        func isExecutable(_ path: String) -> Bool {
            FileManager.default.isExecutableFile(atPath: path)
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") where !directory.isEmpty {
                let candidate = "\(directory)/codex"
                if isExecutable(candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent("bin").path,
        ]
        for directory in commonDirectories where isExecutable("\(directory)/codex") {
            return URL(fileURLWithPath: "\(directory)/codex")
        }
        let roots = applicationsRoots ?? [
            "/Applications",
            homeDirectory.appendingPathComponent("Applications").path,
        ]
        for applicationsRoot in roots {
            for appName in ["ChatGPT", "Codex"] {
                let candidate = "\(applicationsRoot)/\(appName).app/Contents/Resources/codex-cli/bin/codex"
                if isExecutable(candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }

    // MARK: - Fetch

    public func fetch() async throws -> ProviderUsage {
        do {
            return try await fetchAppServer()
        } catch {
            if let fallback = try rolloutFallback() {
                return fallback
            }
            throw error
        }
    }

    private func fetchAppServer() async throws -> ProviderUsage {
        guard let executableURL else {
            throw CodexNotInstalledError()
        }
        let session = try AppServerSession(executableURL: executableURL)
        await session.start()
        do {
            _ = try await session.request(
                id: 1,
                method: "initialize",
                params: ["clientInfo": ["name": "AIUsageMonitor", "version": "1.0.0"], "capabilities": [:] as [String: Any]]
            )
            let result = try await session.request(id: 2, method: "account/rateLimits/read")
            guard let limits = result["rateLimits"] as? [String: Any] else {
                throw SchemaError("Codex rate-limit data is unavailable")
            }
            let resetCredits = result["rateLimitResetCredits"] as? [String: Any]
            let usage = try Self.normalize(limits: limits, resetCredits: resetCredits, stale: false)
            await session.shutdown()
            return usage
        } catch {
            await session.shutdown()
            throw error
        }
    }

    // MARK: - Normalization

    static func field(_ value: [String: Any], _ camel: String, _ snake: String) -> Any? {
        value[camel] ?? value[snake]
    }

    /// Normalizes either the live app-server payload or a local rollout
    /// record. `observedAt` preserves the real observation time of stale
    /// records instead of stamping them with the normalization time.
    public static func normalize(
        limits: [String: Any],
        resetCredits: [String: Any]? = nil,
        stale: Bool,
        observedAt: Date? = nil
    ) throws -> ProviderUsage {
        var mappedFiveHour: UsageWindow?
        var mappedWeekly: UsageWindow?
        for name in ["primary", "secondary"] {
            guard let item = limits[name] as? [String: Any] else { continue }
            guard let minutes = field(item, "windowDurationMins", "window_minutes") else { continue }
            let duration = try number(minutes, "windowDurationMins")
            let used = field(item, "usedPercent", "used_percent")
            let resetAt = field(item, "resetsAt", "resets_at")
            if (270...330).contains(duration) {
                mappedFiveHour = try windowFromPercent("5-hour", usedPercent: used, resetAt: try localFromUnix(resetAt))
            } else if (9000...11000).contains(duration) {
                mappedWeekly = try windowFromPercent("Weekly", usedPercent: used, resetAt: try localFromUnix(resetAt))
            }
        }
        guard mappedFiveHour != nil || mappedWeekly != nil else {
            throw SchemaError("Codex rate-limit data contains no recognized windows")
        }

        var monthly: UsageWindow?
        let individual = limits["individualLimit"] as? [String: Any] ?? limits["individual_limit"] as? [String: Any]
        if let individual {
            let remainingPercent = try number(
                field(individual, "remainingPercent", "remaining_percent"),
                "individualLimit.remainingPercent"
            )
            let used = try number(individual["used"], "individualLimit.used")
            let cap = try number(individual["limit"], "individualLimit.limit")
            let resetAt = try localFromUnix(field(individual, "resetsAt", "resets_at"))
            monthly = try windowFromPercent("Monthly", usedPercent: 100 - remainingPercent, resetAt: resetAt)
            monthly?.used = used
            monthly?.cap = cap
            monthly?.remaining = cap - used
        }

        let credits = limits["credits"] as? [String: Any]
        var balance: Double?
        if let rawBalance = credits?["balance"] {
            if let string = rawBalance as? String, !string.isEmpty {
                balance = Double(string)
            } else if let number = rawBalance as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                balance = number.doubleValue
            }
        }

        let planTypeRaw = limits["planType"] as? String ?? limits["plan_type"] as? String ?? "Codex"
        return ProviderUsage(
            provider: "Codex",
            plan: planTypeRaw.capitalized,
            status: stale ? .stale : .ok,
            fiveHour: mappedFiveHour,
            weekly: mappedWeekly,
            monthly: monthly,
            fetchedAt: observedAt ?? Date(),
            stale: stale,
            error: stale ? "Latest local Codex session record; live refresh unavailable." : nil,
            creditBalance: balance,
            resetCreditsAvailable: (resetCredits?["availableCount"] as? Int) ?? (resetCredits?["available_count"] as? Int)
        )
    }

    // MARK: - Local session fallback

    /// Recursively extracts `rate_limits` dictionaries, mirroring
    /// `_rate_limits_from`.
    static func rateLimitsDicts(in value: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []
        if let dict = value as? [String: Any] {
            for (key, item) in dict {
                if key == "rate_limits", let limits = item as? [String: Any] {
                    results.append(limits)
                }
                results.append(contentsOf: rateLimitsDicts(in: item))
            }
        } else if let list = value as? [Any] {
            for item in list {
                results.append(contentsOf: rateLimitsDicts(in: item))
            }
        }
        return results
    }

    func rolloutFallback() throws -> ProviderUsage? {
        let fileManager = FileManager.default
        let sessions = homeDirectory.appendingPathComponent(".codex/sessions")
        var files: [(url: URL, modified: Date)] = []
        if let enumerator = fileManager.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                files.append((url, modified))
            }
        }
        for entry in files.sorted(by: { $0.modified > $1.modified }).prefix(20) {
            guard let text = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                guard let data = line.data(using: .utf8),
                      let value = (try? JSONSerialization.jsonObject(with: data, options: [])) else {
                    continue
                }
                for limits in Self.rateLimitsDicts(in: value) {
                    let observedAt = Self.observedTimestamp(of: value) ?? entry.modified
                    if let usage = try? Self.normalize(limits: limits, stale: true, observedAt: observedAt) {
                        return usage
                    }
                }
            }
        }
        return nil
    }

    /// Best-effort record timestamp for age-accurate stale data.
    static func observedTimestamp(of record: Any) -> Date? {
        guard let dict = record as? [String: Any],
              let raw = dict["timestamp"] as? String,
              let date = ISO8601.date(from: raw) else {
            return nil
        }
        return date
    }
}

// MARK: - App-server session

/// One owned `codex app-server --stdio` process with a single line reader.
/// Responses are matched to requests by id; interleaved notifications are
/// ignored, and responses that arrive before their waiter register are kept
/// until the matching request consumes them.
actor AppServerSession {
    private let process: Process
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var reader: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<[String: Any], any Error>] = [:]
    private var buffered: [Int: [String: Any]] = [:]
    private var closed = false

    init(executableURL: URL) throws {
        process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CodexNotInstalledError("Codex app-server could not be started")
        }
    }

    /// Starts the single line reader. Called immediately after construction;
    /// actor initializers cannot spawn tasks that touch isolated state.
    func start() {
        guard reader == nil else { return }
        reader = Task { [weak self] in
            await self?.readLines()
        }
    }

    private func readLines() async {
        let handle = stdoutPipe.fileHandleForReading
        var buffer = Data()
        do {
            for try await byte in handle.bytes {
                buffer.append(byte)
                if byte == UInt8(ascii: "\n") {
                    if let string = String(data: buffer, encoding: .utf8), !string.isEmpty {
                        handleLine(string.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            // The process exited or the pipe broke; stop reading.
        }
        finishStream()
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return
        }
        guard let responseID = (value["id"] as? NSNumber)?.intValue else {
            return // A notification, not a response.
        }
        if value["error"] != nil {
            resume(responseID, with: .failure(SchemaError("Codex app-server returned an error")))
            return
        }
        guard let result = value["result"] as? [String: Any] else {
            resume(responseID, with: .failure(SchemaError("Codex app-server returned an unexpected response")))
            return
        }
        resume(responseID, with: .success(result))
    }

    private func resume(_ id: Int, with result: Result<[String: Any], any Error>) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(with: result)
        } else if case .success(let value) = result {
            buffered[id] = value
        }
    }

    private func finishStream() {
        closed = true
        for (_, continuation) in pending {
            continuation.resume(throwing: AppServerTimeoutError())
        }
        pending.removeAll()
    }

    func request(id: Int, method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        if closed {
            throw AppServerTimeoutError()
        }
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params {
            message["params"] = params
        }
        let payload = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        stdinPipe.fileHandleForWriting.write(payload + Data("\n".utf8))
        do {
            return try await withTimeout(seconds: 12) {
                try await self.waitFor(id: id)
            }
        } catch is TimeoutError {
            throw AppServerTimeoutError()
        }
    }

    private func waitFor(id: Int) async throws -> [String: Any] {
        if let bufferedValue = buffered.removeValue(forKey: id) {
            return bufferedValue
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
            }
        } onCancel: {
            Task { await self.resume(id, with: .failure(CancellationError())) }
        }
    }

    func shutdown() async {
        reader?.cancel()
        process.terminate()
        if !process.waitUntilExitWithTimeout(seconds: 3) {
            process.interrupt()
        }
    }
}

private extension Process {
    /// Blocks up to `seconds` for the process to exit; returns false on timeout.
    func waitUntilExitWithTimeout(seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while isRunning && Date() < deadline {
            usleep(100_000)
        }
        return !isRunning
    }
}
