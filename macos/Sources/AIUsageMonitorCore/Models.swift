/// Provider-neutral models shared by every presentation surface.
///
/// Mirrors `models.py`: snake_case JSON keys and status values are kept
/// identical so cached data and diagnostics stay comparable across platforms.
import Foundation

public enum ProviderStatus: String, Codable, Sendable, CaseIterable {
    case ok
    case stale
    case authError = "auth_error"
    case networkError = "network_error"
    case schemaError = "schema_error"
    case apiError = "api_error"
    case codexNotInstalled = "codex_not_installed"
    case notLoggedIn = "not_logged_in"
    case appServerStartFailed = "app_server_start_failed"
    case appServerProtocolError = "app_server_protocol_error"
    case rateLimitDataUnavailable = "rate_limit_data_unavailable"
    case staleLogFallback = "stale_log_fallback"

    /// Human label used by the detail surfaces.
    public var label: String {
        switch self {
        case .ok: "Live"
        case .stale, .staleLogFallback: "Stale"
        case .authError: "Sign-in required"
        case .networkError: "Network error"
        case .schemaError: "Format changed"
        case .apiError: "Unavailable"
        case .codexNotInstalled: "Not installed"
        case .notLoggedIn: "Not signed in"
        case .appServerStartFailed: "Could not start app-server"
        case .appServerProtocolError: "App-server protocol error"
        case .rateLimitDataUnavailable: "Usage data unavailable"
        }
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public var name: String
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetAt: Date?
    public var used: Double?
    public var cap: Double?
    public var remaining: Double?
    public var sourceType: String

    public init(
        name: String,
        usedPercent: Double,
        remainingPercent: Double,
        resetAt: Date? = nil,
        used: Double? = nil,
        cap: Double? = nil,
        remaining: Double? = nil,
        sourceType: String = "usage_window"
    ) {
        self.name = name
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.used = used
        self.cap = cap
        self.remaining = remaining
        self.sourceType = sourceType
    }

    public enum CodingKeys: String, CodingKey {
        case name
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case resetAt = "reset_at"
        case used
        case cap
        case remaining
        case sourceType = "source_type"
    }
}

public struct ProviderUsage: Codable, Equatable, Sendable {
    public var provider: String
    public var plan: String?
    public var status: ProviderStatus
    public var fiveHour: UsageWindow?
    public var weekly: UsageWindow?
    public var monthly: UsageWindow?
    public var fetchedAt: Date
    public var stale: Bool
    public var error: String?
    public var creditBalance: Double?
    public var resetCreditsAvailable: Int?

    public init(
        provider: String,
        plan: String?,
        status: ProviderStatus,
        fiveHour: UsageWindow?,
        weekly: UsageWindow?,
        monthly: UsageWindow?,
        fetchedAt: Date,
        stale: Bool = false,
        error: String? = nil,
        creditBalance: Double? = nil,
        resetCreditsAvailable: Int? = nil
    ) {
        self.provider = provider
        self.plan = plan
        self.status = status
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.monthly = monthly
        self.fetchedAt = fetchedAt
        self.stale = stale
        self.error = error
        self.creditBalance = creditBalance
        self.resetCreditsAvailable = resetCreditsAvailable
    }

    public enum CodingKeys: String, CodingKey {
        case provider, plan, status
        case fiveHour = "five_hour"
        case weekly, monthly
        case fetchedAt = "fetched_at"
        case stale, error
        case creditBalance = "credit_balance"
        case resetCreditsAvailable = "reset_credits_available"
    }

    /// The non-nil windows in presentation order.
    public func windows() -> [UsageWindow] {
        [fiveHour, weekly, monthly].compactMap { $0 }
    }

    /// A failure entry with no windows, mirroring `UsageService._failure`.
    public static func unavailable(providerName: String, status: ProviderStatus, fetchedAt: Date, error: String? = nil) -> ProviderUsage {
        ProviderUsage(
            provider: providerName,
            plan: nil,
            status: status,
            fiveHour: nil,
            weekly: nil,
            monthly: nil,
            fetchedAt: fetchedAt,
            stale: false,
            error: error
        )
    }

    /// Returns a copy flagged stale while preserving the observed values,
    /// mirroring the cached-fallback behavior in `service.py`.
    public func markingStale(status: ProviderStatus, error: String?) -> ProviderUsage {
        var copy = self
        copy.status = status
        copy.stale = true
        copy.error = error
        return copy
    }
}

public protocol UsageProvider: Sendable {
    var key: String { get }
    var displayName: String { get }
    func fetch() async throws -> ProviderUsage
}

public extension UsageProvider {
    var displayName: String { key.replacingOccurrences(of: "opencode", with: "opencode go").capitalized }
}
