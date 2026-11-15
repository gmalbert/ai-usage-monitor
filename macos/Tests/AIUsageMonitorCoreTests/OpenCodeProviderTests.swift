import XCTest
@testable import AIUsageMonitorCore

final class InMemoryKeychain: OpenCodeKeyStorage, @unchecked Sendable {
    var key: String?
    func loadKey() -> String? { key }
}

final class OpenCodeProviderTests: XCTestCase {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aium-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func usagePayload(rolling: Int = 0, weekly: Int = 1, monthly: Int = 14) -> [String: Any] {
        [
            "usage": [
                "rolling": ["percent": rolling, "resetsAt": "2026-09-01T12:00:00Z"],
                "weekly": ["percent": weekly, "resetsAt": "2026-09-01T12:00:00Z"],
                "monthly": ["percent": monthly, "resetsAt": "2026-09-01T12:00:00Z"],
            ],
        ]
    }

    func testNormalizesAllWindows() async throws {
        let provider = OpenCodeGoProvider(
            apiKey: "test-key",
            keychain: InMemoryKeychain(),
            transport: MockTransport(responses: [usagePayload()])
        )
        let usage = try await provider.fetch()
        XCTAssertEqual(usage.provider, "OpenCode Go")
        XCTAssertEqual(usage.monthly?.remainingPercent, 86)
        XCTAssertEqual(usage.fiveHour?.remainingPercent, 100)
        XCTAssertEqual(usage.weekly?.remainingPercent, 99)
    }

    func testMissingMonthlyIsRejected() async throws {
        var payload = usagePayload()
        var usage = payload["usage"] as! [String: Any]
        usage.removeValue(forKey: "monthly")
        payload["usage"] = usage
        let provider = OpenCodeGoProvider(
            apiKey: "test-key",
            keychain: InMemoryKeychain(),
            transport: MockTransport(responses: [payload])
        )
        do {
            _ = try await provider.fetch()
            XCTFail("Expected a schema error")
        } catch {
            XCTAssertTrue(error is SchemaError)
        }
    }

    func testKeyResolutionOrderUsesEnvironmentBeforeKeychain() async throws {
        let keychain = InMemoryKeychain()
        keychain.key = "keychain-key"

        let fromKeychain = MockTransport(responses: [usagePayload()])
        let providerWithKeychain = OpenCodeGoProvider(keychain: keychain, transport: fromKeychain, environment: [:])
        _ = try await providerWithKeychain.fetch()
        XCTAssertEqual(fromKeychain.recordedRequests.first?.token, "keychain-key")

        let fromEnvironment = MockTransport(responses: [usagePayload()])
        let providerWithEnv = OpenCodeGoProvider(
            keychain: keychain,
            transport: fromEnvironment,
            environment: ["OPENCODE_GO_API_KEY": "env-key"]
        )
        _ = try await providerWithEnv.fetch()
        XCTAssertEqual(fromEnvironment.recordedRequests.first?.token, "env-key")

        let fromExplicit = MockTransport(responses: [usagePayload()])
        let providerWithExplicit = OpenCodeGoProvider(
            apiKey: "explicit-key",
            keychain: keychain,
            transport: fromExplicit,
            environment: ["OPENCODE_GO_API_KEY": "env-key"]
        )
        _ = try await providerWithExplicit.fetch()
        XCTAssertEqual(fromExplicit.recordedRequests.first?.token, "explicit-key")
    }

    func testMissingKeyThrowsClearError() async {
        let provider = OpenCodeGoProvider(
            keychain: InMemoryKeychain(),
            homeDirectory: temporaryDirectory,
            transport: MockTransport(responses: [usagePayload()]),
            environment: [:]
        )
        do {
            _ = try await provider.fetch()
            XCTFail("Expected a missing-key error")
        } catch {}
    }

    func testReadsExistingOpenCodeCredentialFile() async throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory.appendingPathComponent(".config/opencode"),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: ["api_key": "file-key"]).write(
            to: temporaryDirectory.appendingPathComponent(".config/opencode/auth.json")
        )
        let provider = OpenCodeGoProvider(
            keychain: InMemoryKeychain(),
            homeDirectory: temporaryDirectory,
            transport: MockTransport(responses: [usagePayload()]),
            environment: [:]
        )
        let usage = try await provider.fetch()
        XCTAssertEqual(usage.status, .ok)
    }
}
