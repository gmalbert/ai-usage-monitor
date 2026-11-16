import XCTest
@testable import AIUsageMonitorCore

final class ModelsTests: XCTestCase {
    func testWindowsReturnsOnlyPresentWindowsInOrder() {
        let usage = ProviderUsage(
            provider: "CommandCode",
            plan: "GOAT",
            status: .ok,
            fiveHour: UsageWindow(name: "5-hour", usedPercent: 10, remainingPercent: 90),
            weekly: nil,
            monthly: UsageWindow(name: "Monthly", usedPercent: 40, remainingPercent: 60),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(usage.windows().map(\.name), ["5-hour", "Monthly"])
    }

    func testMarkingStalePreservesValuesButFlipsStatus() {
        let window = UsageWindow(name: "5-hour", usedPercent: 10, remainingPercent: 90)
        let usage = ProviderUsage(
            provider: "Codex", plan: "Plus", status: .ok,
            fiveHour: window, weekly: nil, monthly: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let stale = usage.markingStale(status: .stale, error: "Network failed")
        XCTAssertTrue(stale.stale)
        XCTAssertEqual(stale.status, .stale)
        XCTAssertEqual(stale.error, "Network failed")
        XCTAssertEqual(stale.fiveHour?.remainingPercent, 90)
        XCTAssertEqual(stale.fetchedAt, usage.fetchedAt)
    }

    func testCodableUsesSnakeCaseJSONKeys() throws {
        let window = UsageWindow(
            name: "Weekly",
            usedPercent: 26.5,
            remainingPercent: 73.5,
            resetAt: Date(timeIntervalSince1970: 1_700_000_000),
            used: 9.36,
            cap: 35,
            remaining: 25.64
        )
        let usage = ProviderUsage(
            provider: "CommandCode", plan: "GOAT", status: .ok,
            fiveHour: nil, weekly: window, monthly: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            creditBalance: 12.5,
            resetCreditsAvailable: 2
        )
        let data = try JSONEncoder.withISODates().encode(usage)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["five_hour"]) // nil optionals are omitted
        let weekly = try XCTUnwrap(object["weekly"] as? [String: Any])
        XCTAssertEqual(weekly["used_percent"] as? Double, 26.5)
        XCTAssertEqual(weekly["remaining_percent"] as? Double, 73.5)
        XCTAssertNotNil(weekly["reset_at"])
        XCTAssertEqual(weekly["cap"] as? Double, 35)
        XCTAssertTrue(object["fetched_at"] is String)
        XCTAssertEqual(object["credit_balance"] as? Double, 12.5)
        XCTAssertEqual(object["reset_credits_available"] as? Int, 2)

        let decoded = try JSONDecoder.withISODates().decode(ProviderUsage.self, from: data)
        XCTAssertEqual(decoded, usage)
    }

    func testStatusRawValuesMatchReference() {
        XCTAssertEqual(ProviderStatus.ok.rawValue, "ok")
        XCTAssertEqual(ProviderStatus.stale.rawValue, "stale")
        XCTAssertEqual(ProviderStatus.authError.rawValue, "auth_error")
        XCTAssertEqual(ProviderStatus.codexNotInstalled.rawValue, "codex_not_installed")
        XCTAssertEqual(ProviderStatus.rateLimitDataUnavailable.rawValue, "rate_limit_data_unavailable")
    }
}
