import XCTest
@testable import AIUsageMonitorCore

final class CodexProviderTests: XCTestCase {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aium-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func liveLimits(
        individual: Bool = false,
        plan: String = "plus"
    ) -> [String: Any] {
        var limits: [String: Any] = [
            "limitId": "codex",
            "primary": ["usedPercent": 38, "windowDurationMins": 300, "resetsAt": 1_794_767_396],
            "secondary": ["usedPercent": 29, "windowDurationMins": 10_080, "resetsAt": 1_795_228_968],
            "credits": ["hasCredits": false, "unlimited": false, "balance": "0"],
            "planType": plan,
        ]
        if individual {
            limits["individualLimit"] = [
                "remainingPercent": 55,
                "used": 45,
                "limit": 100,
                "resetsAt": 1_796_068_200,
            ]
        }
        return limits
    }

    func testNormalizeMapsLiveWindows() throws {
        let usage = try CodexProvider.normalize(
            limits: liveLimits(),
            resetCredits: ["availableCount": 3],
            stale: false
        )
        XCTAssertEqual(usage.provider, "Codex")
        XCTAssertEqual(usage.plan, "Plus")
        XCTAssertEqual(usage.fiveHour?.remainingPercent, 62)
        XCTAssertEqual(usage.weekly?.remainingPercent, 71)
        XCTAssertNil(usage.monthly)
        XCTAssertEqual(usage.creditBalance, 0)
        XCTAssertEqual(usage.resetCreditsAvailable, 3)
        XCTAssertEqual(usage.status, .ok)
        XCTAssertFalse(usage.stale)
    }

    func testNormalizeMapsOptionalMonthlyIndividualLimit() throws {
        let usage = try CodexProvider.normalize(
            limits: liveLimits(individual: true),
            resetCredits: nil,
            stale: false
        )
        XCTAssertEqual(usage.monthly?.name, "Monthly")
        XCTAssertEqual(usage.monthly?.usedPercent, 45)
        XCTAssertEqual(usage.monthly?.cap, 100)
        XCTAssertEqual(usage.monthly?.remaining, 55)
    }

    func testNormalizeAcceptsSnakeCaseFields() throws {
        let limits: [String: Any] = [
            "primary": ["used_percent": 40, "window_minutes": 300, "resets_at": 1_794_767_396],
        ]
        let usage = try CodexProvider.normalize(limits: limits, stale: false)
        XCTAssertEqual(usage.fiveHour?.remainingPercent, 60)
        XCTAssertNil(usage.weekly)
    }

    func testNormalizeRejectsUnrecognizedWindows() {
        let limits: [String: Any] = [
            "primary": ["usedPercent": 10, "windowDurationMins": 60, "resetsAt": 1_794_767_396],
        ]
        XCTAssertThrowsError(try CodexProvider.normalize(limits: limits, stale: false)) { error in
            XCTAssertTrue(error is SchemaError)
            XCTAssertEqual((error as! SchemaError).message, "Codex rate-limit data contains no recognized windows")
        }
    }

    func testStaleNormalizationPreservesObservationTime() throws {
        let observed = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = try CodexProvider.normalize(limits: liveLimits(), stale: true, observedAt: observed)
        XCTAssertTrue(usage.stale)
        XCTAssertEqual(usage.status, .stale)
        XCTAssertEqual(usage.fetchedAt, observed)
        XCTAssertEqual(usage.error, "Latest local Codex session record; live refresh unavailable.")
    }

    func testRateLimitsExtractionIsRecursive() {
        let payload: [String: Any] = [
            "timestamp": "2026-11-15T00:00:24.000Z",
            "payload": [
                "nested": [
                    ["rate_limits": ["primary": ["usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1_794_767_396]]],
                ],
            ],
        ]
        let extracted = CodexProvider.rateLimitsDicts(in: payload)
        XCTAssertEqual(extracted.count, 1)
        XCTAssertEqual((extracted[0]["primary"] as? [String: Any])?["usedPercent"] as? Int, 20)
    }

    func testObservedTimestampPrefersRecordTimestamp() {
        let record: [String: Any] = ["timestamp": "2026-11-15T00:00:24.000Z"]
        XCTAssertEqual(CodexProvider.observedTimestamp(of: record)?.timeIntervalSince1970, 1_794_700_824)
        XCTAssertNil(CodexProvider.observedTimestamp(of: ["other": 1]))
    }

    func testRolloutFallbackUsesMostRecentRecordAndPreservesAge() throws {
        let sessions = temporaryDirectory.appendingPathComponent(".codex/sessions/2026/11/15")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let record: [String: Any] = [
            "timestamp": "2026-11-15T00:00:24.000Z",
            "rate_limits": [
                "primary": ["usedPercent": 26, "windowDurationMins": 300, "resetsAt": 1_794_767_396],
                "secondary": ["usedPercent": 12, "windowDurationMins": 10_080, "resetsAt": 1_795_228_968],
                "planType": "plus",
            ],
        ]
        let line = String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        try (line + "\n").write(
            to: sessions.appendingPathComponent("rollout-2026-11-15T.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let provider = CodexProvider(
            executableURL: nil,
            homeDirectory: temporaryDirectory
        )
        let usage = try provider.rolloutFallback()
        XCTAssertNotNil(usage)
        XCTAssertTrue(usage!.stale)
        XCTAssertEqual(usage!.fiveHour?.remainingPercent, 74)
        XCTAssertEqual(usage!.fetchedAt.timeIntervalSince1970, 1_794_700_824, accuracy: 1)
    }

    func testExecutableDiscoveryFindsDesktopBundle() throws {
        let home = temporaryDirectory
        let bundleExecutable = home.appendingPathComponent(
            "Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        )
        try FileManager.default.createDirectory(
            at: bundleExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: bundleExecutable.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundleExecutable.path)

        let found = CodexProvider.locateExecutable(
            environment: ["PATH": "/usr/bin"],
            homeDirectory: home,
            applicationsRoots: [home.appendingPathComponent("Applications").path]
        )
        XCTAssertEqual(found?.path, bundleExecutable.path)
    }

    func testExecutableDiscoveryUsesPATHFirst() throws {
        let directory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let found = CodexProvider.locateExecutable(environment: ["PATH": directory.path], homeDirectory: temporaryDirectory)
        XCTAssertEqual(found?.path, executable.path)
    }

    func testMissingExecutableFallsBackToLocalRecord() async throws {
        let sessions = temporaryDirectory.appendingPathComponent(".codex/sessions/sub")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let record: [String: Any] = [
            "timestamp": "2026-11-15T00:00:24.000Z",
            "rate_limits": ["primary": ["usedPercent": 26, "windowDurationMins": 300, "resetsAt": 1_794_767_396]],
        ]
        let line = String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        try (line + "\n").write(
            to: sessions.appendingPathComponent("rollout.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let provider = CodexProvider(
            executableURL: URL(fileURLWithPath: "/nonexistent/codex"),
            homeDirectory: temporaryDirectory
        )
        // The app-server cannot start, so fetch() returns the local stale record.
        let usage = try await provider.fetch()
        XCTAssertTrue(usage.stale)
        XCTAssertEqual(usage.status, .stale)
        XCTAssertEqual(usage.fiveHour?.remainingPercent, 74)
    }
}
