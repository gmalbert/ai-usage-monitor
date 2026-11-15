import XCTest
@testable import AIUsageMonitorCore

final class MockProvider: UsageProvider, @unchecked Sendable {
    let key: String
    let displayName: String
    var nextResult: Result<ProviderUsage, any Error>
    private(set) var fetchCount = 0

    init(key: String, result: Result<ProviderUsage, any Error>, displayName: String? = nil) {
        self.key = key
        self.nextResult = result
        self.displayName = displayName ?? key.capitalized
    }
    func fetch() async throws -> ProviderUsage {
        fetchCount += 1
        return try nextResult.get()
    }
}

func liveUsage(
    key: String,
    name: String,
    fiveHour: Double? = 80,
    weekly: Double? = 70,
    monthly: Double? = 60
) -> ProviderUsage {
    func window(_ name: String, _ remaining: Double?) -> UsageWindow? {
        guard let remaining else { return nil }
        return UsageWindow(name: name, usedPercent: 100 - remaining, remainingPercent: remaining)
    }
    return ProviderUsage(
        provider: name, plan: nil, status: .ok,
        fiveHour: window("5-hour", fiveHour),
        weekly: window("Weekly", weekly),
        monthly: window("Monthly", monthly),
        fetchedAt: Date()
    )
}

final class UsageServiceTests: XCTestCase {
    var privatePath: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aium-\(UUID().uuidString)-cache.json")
    }

    func testFailureClassificationMirrorsReference() {
        XCTAssertEqual(UsageService.status(for: CodexNotInstalledError()), .codexNotInstalled)
        XCTAssertEqual(UsageService.status(for: ProviderHTTPError(statusCode: 401)), .authError)
        XCTAssertEqual(UsageService.status(for: ProviderHTTPError(statusCode: 403)), .authError)
        XCTAssertEqual(UsageService.status(for: ProviderHTTPError(statusCode: 429)), .apiError)
        XCTAssertEqual(UsageService.status(for: NetworkRequestError()), .networkError)
        XCTAssertEqual(UsageService.status(for: AppServerTimeoutError()), .networkError)
        XCTAssertEqual(UsageService.status(for: SchemaError("changed")), .schemaError)
        XCTAssertEqual(UsageService.status(for: NSError(domain: "test", code: 1)), .apiError)
    }

    func testOneFailureDoesNotHideSuccessfulResults() async {
        let good = MockProvider(key: "commandcode", result: .success(liveUsage(key: "commandcode", name: "CommandCode")))
        let bad = MockProvider(key: "opencode", result: .failure(NetworkRequestError("offline")))
        let service = UsageService(providers: [good, bad], cache: UsageCache(path: privatePath))
        let values = await service.refresh()
        XCTAssertEqual(values["commandcode"]?.status, .ok)
        XCTAssertEqual(values["opencode"]?.status, .networkError)
        XCTAssertEqual(values["opencode"]?.provider, "Opencode")
    }

    func testFailurePreservesOldValuesAsStale() async {
        let old = liveUsage(key: "codex", name: "Codex", fiveHour: 30)
        let failing = MockProvider(key: "codex", result: .failure(CodexNotInstalledError()))
        let service = UsageService(providers: [failing], cache: UsageCache(path: privatePath))
        await service.replaceValues(["codex": old])
        let values = await service.refresh()
        let codex = values["codex"]
        XCTAssertEqual(codex?.status, .stale)
        XCTAssertEqual(codex?.stale, true)
        XCTAssertEqual(codex?.fiveHour?.remainingPercent, 30)
        XCTAssertNotNil(codex?.error)
    }

    func testLowestRemainingExcludesStaleAndUnavailable() async {
        let service = UsageService(providers: [], cache: UsageCache(path: privatePath))
        await service.replaceValues([
            "commandcode": liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 42),
            "codex": liveUsage(key: "codex", name: "Codex", fiveHour: 10).markingStale(status: .stale, error: "stale"),
            "opencode": ProviderUsage.unavailable(
                providerName: "OpenCode Go", status: .authError, fetchedAt: Date(), error: "no key"
            ),
        ])
        let lowest = await service.lowestRemaining()
        XCTAssertEqual(lowest, 42)
    }

    func testLowestRemainingNilWhenNoLiveData() async {
        let service = UsageService(providers: [], cache: UsageCache(path: privatePath))
        let lowest = await service.lowestRemaining()
        XCTAssertNil(lowest)
    }

    func testThresholdEventsFireOnlyOnDownwardTransitions() async {
        let provider = MockProvider(key: "commandcode", result: .success(liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 45)))
        let service = UsageService(providers: [provider], cache: UsageCache(path: privatePath))
        let settings = AppSettings()

        // normal -> warning
        _ = await service.refresh()
        let first = await service.evaluateThresholds(settings: settings)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].level, .warning)
        XCTAssertEqual(first[0].windowName, "5-hour")

        // warning -> warning: no repeat
        let second = await service.evaluateThresholds(settings: settings)
        XCTAssertTrue(second.isEmpty)

        // warning -> critical: downward, fires
        provider.nextResult = .success(liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 15))
        _ = await service.refresh()
        let third = await service.evaluateThresholds(settings: settings)
        XCTAssertEqual(third.count, 1)
        XCTAssertEqual(third[0].level, .critical)

        // critical -> warning: upward recovery, must not fire
        provider.nextResult = .success(liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 45))
        _ = await service.refresh()
        let fourth = await service.evaluateThresholds(settings: settings)
        XCTAssertTrue(fourth.isEmpty)

        // warning -> normal: no event
        provider.nextResult = .success(liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 99))
        _ = await service.refresh()
        let fifth = await service.evaluateThresholds(settings: settings)
        XCTAssertTrue(fifth.isEmpty)

        // normal -> critical directly: fires once
        provider.nextResult = .success(liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 5))
        _ = await service.refresh()
        let sixth = await service.evaluateThresholds(settings: settings)
        XCTAssertEqual(sixth.count, 1)
        XCTAssertEqual(sixth[0].level, .critical)
    }

    func testThresholdEventsIgnoreStaleData() async {
        let provider = MockProvider(
            key: "codex",
            result: .success(
                liveUsage(key: "codex", name: "Codex", fiveHour: 5)
                    .markingStale(status: .stale, error: "stale")
            )
        )
        let service = UsageService(providers: [provider], cache: UsageCache(path: privatePath))
        let result = await service.evaluateThresholds(settings: AppSettings())
        XCTAssertTrue(result.isEmpty)
    }

    func testRefreshSavesToCache() async {
        let path = privatePath
        let service = UsageService(
            providers: [MockProvider(key: "commandcode", result: .success(liveUsage(key: "commandcode", name: "CommandCode")))],
            cache: UsageCache(path: path)
        )
        _ = await service.refresh()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let reloaded = UsageCache(path: path).load()
        XCTAssertEqual(reloaded["commandcode"]?.fiveHour?.remainingPercent, 80)
        // Startup cache loads as stale, never as live data.
        XCTAssertEqual(reloaded["commandcode"]?.status, .stale)
        XCTAssertEqual(reloaded["commandcode"]?.stale, true)
    }

    func testSerializedRefreshesDoNotOverlap() async {
        let provider = MockProvider(key: "commandcode", result: .success(liveUsage(key: "commandcode", name: "CommandCode")))
        let service = UsageService(providers: [provider], cache: UsageCache(path: privatePath))
        async let first = service.refresh()
        async let second = service.refresh()
        _ = await (first, second)
        XCTAssertEqual(provider.fetchCount, 2)
    }
}
