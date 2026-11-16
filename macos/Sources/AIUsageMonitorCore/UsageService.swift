/// Concurrent refresh, cache fallback, and threshold transitions.
/// Mac counterpart of `service.py`, restructured as an actor so refreshes are
/// serialized (the reference implementation allowed overlapping refreshes).
import Foundation

public struct ThresholdEvent: Equatable, Sendable {
    public enum Level: String, Sendable {
        case warning
        case critical
    }

    public let providerName: String
    public let windowName: String
    public let remainingPercent: Double
    public let level: Level
}

public actor UsageService {
    public private(set) var values: [String: ProviderUsage]
    /// Previous per-meter states used to detect downward threshold crossings.
    public private(set) var thresholdStates: [String: String] = [:]

    private let providers: [any UsageProvider]
    private let cache: UsageCache
    private let now: @Sendable () -> Date

    public init(
        providers: [any UsageProvider],
        cache: UsageCache? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = providers
        self.cache = cache ?? UsageCache()
        self.now = now
        self.values = self.cache.load()
    }

    /// Refreshes every provider concurrently. One provider's failure never
    /// hides another's results; the previous value is preserved as stale.
    public func refresh() async -> [String: ProviderUsage] {
        let providersByKey = Dictionary(uniqueKeysWithValues: providers.map { ($0.key, $0) })
        await withTaskGroup(of: (String, Result<ProviderUsage, any Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider.key, .success(try await provider.fetch()))
                    } catch {
                        return (provider.key, .failure(error))
                    }
                }
            }
            for await (key, result) in group {
                switch result {
                case .success(let usage):
                    values[key] = usage
                case .failure(let error):
                    let provider = providersByKey[key]
                    values[key] = provider.map {
                        Self.failureEntry(provider: $0, error: error, old: values[key], at: now())
                    }
                }
            }
        }
        cache.save(values)
        return values
    }

    public func lowestRemaining() -> Double? {
        let candidates = values.values
            .filter { $0.status == .ok }
            .flatMap { usage in usage.windows().map { $0.remainingPercent } }
        return candidates.min()
    }

    // MARK: - Failure handling

    /// Classifies a thrown error into a status, mirroring `_failure()`.
    static func status(for error: any Error) -> ProviderStatus {
        if error is CodexNotInstalledError {
            return .codexNotInstalled
        }
        if let http = error as? ProviderHTTPError, http.statusCode == 401 || http.statusCode == 403 {
            return .authError
        }
        if error is NetworkRequestError || error is AppServerTimeoutError {
            return .networkError
        }
        if error is SchemaError {
            return .schemaError
        }
        return .apiError
    }

    static func failureEntry(
        provider: any UsageProvider,
        error: any Error,
        old: ProviderUsage?,
        at date: Date
    ) -> ProviderUsage {
        let status = status(for: error)
        if let old {
            return old.markingStale(status: .stale, error: sanitizedMessage(error))
        }
        return ProviderUsage.unavailable(
            providerName: provider.displayName,
            status: status,
            fetchedAt: date,
            error: sanitizedMessage(error)
        )
    }

    /// Errors are surfaced without credentials or response bodies.
    static func sanitizedMessage(_ error: any Error) -> String {
        let described = (error as CustomStringConvertible).description
        if !described.isEmpty {
            return described
        }
        return "Provider refresh failed"
    }

    // MARK: - Threshold transitions

    /// Emits events only for downward crossings into warning/critical, and
    /// only from live data. Fixes the reference behavior where any transition
    /// (including recovery from critical to warning) could notify.
    public func evaluateThresholds(settings: AppSettings) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        for (providerKey, usage) in values {
            guard usage.status == .ok, !usage.stale else { continue }
            for window in usage.windows() {
                let key = "\(providerKey):\(window.name)"
                let level: ThresholdEvent.Level? = {
                    if window.remainingPercent < settings.criticalThreshold {
                        return .critical
                    }
                    if window.remainingPercent < settings.warningThreshold {
                        return .warning
                    }
                    return nil
                }()
                let previous = thresholdStates[key] ?? "normal"
                if let level, Self.isDownward(previous: previous, current: level) {
                    events.append(
                        ThresholdEvent(
                            providerName: usage.provider,
                            windowName: window.name,
                            remainingPercent: window.remainingPercent,
                            level: level
                        )
                    )
                }
                thresholdStates[key] = level?.rawValue ?? "normal"
            }
        }
        return events
    }

    static func isDownward(previous: String, current: ThresholdEvent.Level) -> Bool {
        switch (previous, current) {
        case ("normal", .warning), ("normal", .critical), ("warning", .critical):
            return true
        default:
            return false
        }
    }

    // MARK: - Snapshot

    public func snapshot(settings: AppSettings) -> UsageSnapshot {
        UsageSnapshot.make(from: values, settings: settings, savedAt: now())
    }

    public func persistCache() {
        cache.save(values)
    }

    /// Replaces the in-memory values. Intended for previews and unit tests.
    public func replaceValues(_ newValues: [String: ProviderUsage]) {
        values = newValues
    }
}
