import XCTest
@testable import AIUsageMonitorCore

final class MockTransport: ProviderTransport, @unchecked Sendable {
    var responses: [[String: Any]]
    var recordedRequests: [(url: URL, token: String, params: [String: String?]?)] = []

    init(responses: [[String: Any]]) {
        self.responses = responses
    }

    func getJSON(_ url: URL, token: String, params: [String: String?]?) async throws -> [String: Any] {
        recordedRequests.append((url, token, params))
        guard !responses.isEmpty else {
            throw NetworkRequestError("No fixture responses remain")
        }
        return responses.removeFirst()
    }
}

final class CommandCodeProviderTests: XCTestCase {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aium-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func authFile() throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["apiKey": "test-key"]).write(to: url)
        return url
    }

    func responses(plan: String = "individual-goat", org: Bool = true) -> [[String: Any]] {
        [
            ["org": org ? ["id": "org-1"] : NSNull()],
            [
                "windowLimits": [
                    "fiveHour": ["used": 1, "cap": 10, "resetAt": 1_700_000_000_000],
                    "weekly": ["used": 2, "cap": 20, "resetAt": 1_700_000_000_000],
                ],
            ],
            [
                "data": [
                    "planId": plan,
                    "status": "active",
                    "currentPeriodStart": "2026-08-01",
                    "currentPeriodEnd": 1_700_000_000_000,
                ],
            ],
            ["totalMonthlyCredits": 7, "periodBasis": "billing-period"],
        ]
    }

    func testNormalizesCreditsAndPlan() async throws {
        let transport = MockTransport(responses: responses())
        let provider = CommandCodeProvider(authURL: try authFile(), transport: transport)
        let usage = try await provider.fetch()
        XCTAssertEqual(usage.provider, "CommandCode")
        XCTAssertEqual(usage.plan, "GOAT")
        XCTAssertEqual(usage.monthly?.remaining, 63)
        XCTAssertEqual(usage.fiveHour?.remainingPercent, 90)
        XCTAssertEqual(usage.weekly?.remainingPercent, 90)
        XCTAssertEqual(usage.status, .ok)
    }

    func testSummaryRequestIncludesSinceAndOrgID() async throws {
        let transport = MockTransport(responses: responses())
        let provider = CommandCodeProvider(authURL: try authFile(), transport: transport)
        _ = try await provider.fetch()
        let summaryRequest = transport.recordedRequests.last
        XCTAssertEqual(summaryRequest?.url.absoluteString, "https://api.commandcode.ai/alpha/usage/summary")
        XCTAssertEqual(summaryRequest?.params?["since"], "2026-08-01")
        XCTAssertEqual(summaryRequest?.params?["orgId"], "org-1")
    }

    func testOmitsMissingOrgID() async throws {
        let transport = MockTransport(responses: responses(org: false))
        let provider = CommandCodeProvider(authURL: try authFile(), transport: transport)
        _ = try await provider.fetch()
        let params = transport.recordedRequests.last?.params ?? [:]
        XCTAssertNil(params["orgId"] ?? nil)
        XCTAssertEqual(params["since"], "2026-08-01")
    }

    func testUnknownPlanIsRejected() async throws {
        let transport = MockTransport(responses: responses(plan: "new-plan"))
        let provider = CommandCodeProvider(authURL: try authFile(), transport: transport)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected a schema error")
        } catch {
            XCTAssertTrue(error is SchemaError)
            XCTAssertEqual((error as! SchemaError).message, "Unknown CommandCode plan ID")
        }
    }

    func testMissingWindowLimitsIsRejected() async throws {
        var fixtures = responses()
        fixtures[1] = ["unexpected": true]
        let transport = MockTransport(responses: fixtures)
        let provider = CommandCodeProvider(authURL: try authFile(), transport: transport)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected a schema error")
        } catch {
            XCTAssertTrue(error is SchemaError)
        }
    }

    func testMissingAuthFileIsRejected() async throws {
        let provider = CommandCodeProvider(
            authURL: temporaryDirectory.appendingPathComponent("nope.json"),
            transport: MockTransport(responses: responses())
        )
        do {
            _ = try await provider.fetch()
            XCTFail("Expected an auth error")
        } catch {}
    }
}
