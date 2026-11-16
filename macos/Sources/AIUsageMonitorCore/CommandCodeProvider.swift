/// CommandCode adapter. Port of `providers/commandcode.py`.
///
/// Reads `~/.commandcode/auth.json` (field `apiKey`), calls the internal
/// `/alpha/` endpoints with the required monitor user agent, and maps plan IDs
/// to centralized monthly credit caps.
import Foundation

public struct CommandCodeProvider: UsageProvider {
    public let key = "commandcode"
    public var displayName: String { "CommandCode" }

    public static let baseURL = URL(string: "https://api.commandcode.ai")!
    public static let planCredits: [String: Double] = [
        "individual-go": 10,
        "individual-provider": 15,
        "individual-pro": 30,
        "teams-pro": 40,
        "individual-goat": 70,
        "individual-pro-v1": 80,
        "individual-max": 150,
        "individual-ultra": 300,
    ]

    private let authURL: URL
    private let transport: any ProviderTransport

    public init(authURL: URL? = nil, transport: any ProviderTransport = URLSessionTransport()) {
        self.authURL = authURL
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".commandcode/auth.json")
        self.transport = transport
    }

    struct AuthFileError: Error, CustomStringConvertible {
        let description: String
    }

    func token() throws -> String {
        guard let data = try? Data(contentsOf: authURL) else {
            throw AuthFileError(description: "CommandCode authentication file is missing or invalid")
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw AuthFileError(description: "CommandCode authentication file is missing or invalid")
        }
        guard let object = value as? [String: Any],
              let apiKey = object["apiKey"] as? String,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthFileError(description: "CommandCode authentication file has no apiKey")
        }
        return apiKey
    }

    public func fetch() async throws -> ProviderUsage {
        let token = try token()
        let whoami = try await transport.getJSON(Self.baseURL.appendingPathComponent("alpha/whoami"), token: token, params: nil)
        let credits = try await transport.getJSON(Self.baseURL.appendingPathComponent("alpha/billing/credits"), token: token, params: nil)
        let subscription = try await transport.getJSON(Self.baseURL.appendingPathComponent("alpha/billing/subscriptions"), token: token, params: nil)

        guard let data = subscription["data"] as? [String: Any] else {
            throw SchemaError("CommandCode subscription is missing")
        }
        guard let planID = data["planId"] as? String, let cap = Self.planCredits[planID] else {
            throw SchemaError("Unknown CommandCode plan ID")
        }
        let periodStart = data["currentPeriodStart"] as? String
        let periodEnd = data["currentPeriodEnd"]

        let org = whoami["org"] as? [String: Any]
        let orgID = org?["id"] as? String
        let summary = try await transport.getJSON(
            Self.baseURL.appendingPathComponent("alpha/usage/summary"),
            token: token,
            params: ["since": periodStart, "orgId": orgID]
        )

        guard let windows = credits["windowLimits"] as? [String: Any] else {
            throw SchemaError("CommandCode API format changed: windowLimits is missing")
        }
        guard let five = windows["fiveHour"] as? [String: Any],
              let weekly = windows["weekly"] as? [String: Any] else {
            throw SchemaError("CommandCode API format changed: rolling windows are missing")
        }

        let monthly = try windowFromUsedAndCap("Monthly", used: summary["totalMonthlyCredits"], cap: cap, resetAt: periodEnd)
        return ProviderUsage(
            provider: "CommandCode",
            plan: planID.hasPrefix("individual-")
                ? String(planID.dropFirst("individual-".count)).uppercased()
                : planID.uppercased(),
            status: .ok,
            fiveHour: try windowFromUsedAndCap("5-hour", used: five["used"], cap: five["cap"], resetAt: five["resetAt"]),
            weekly: try windowFromUsedAndCap("Weekly", used: weekly["used"], cap: weekly["cap"], resetAt: weekly["resetAt"]),
            monthly: monthly,
            fetchedAt: Date()
        )
    }
}
