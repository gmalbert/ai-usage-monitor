import XCTest
@testable import AIUsageMonitorCore

final class CacheAndSettingsTests: XCTestCase {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aium-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - Cache

    func testCacheSaveLoadRoundTrip() {
        let path = temporaryDirectory.appendingPathComponent("nested/cache.json")
        let cache = UsageCache(path: path)
        let usage = liveUsage(key: "commandcode", name: "CommandCode")
        cache.save(["commandcode": usage])
        let loaded = cache.load()
        XCTAssertEqual(loaded["commandcode"]?.fiveHour?.remainingPercent, 80)
        XCTAssertEqual(loaded["commandcode"]?.plan, nil)
    }

    func testCacheLoadMarksDataStale() {
        let path = temporaryDirectory.appendingPathComponent("cache.json")
        let cache = UsageCache(path: path)
        cache.save(["commandcode": liveUsage(key: "commandcode", name: "CommandCode")])
        let loaded = cache.load()["commandcode"]
        XCTAssertEqual(loaded?.status, .stale)
        XCTAssertEqual(loaded?.stale, true)
        XCTAssertNotNil(loaded?.error)
    }

    func testCacheLoadToleratesCorruptedFile() throws {
        let path = temporaryDirectory.appendingPathComponent("cache.json")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try "garbage{{".write(to: path, atomically: true, encoding: .utf8)
        let cache = UsageCache(path: path)
        XCTAssertTrue(cache.load().isEmpty)
    }

    func testCacheDefaultPathIsUnderLibraryCaches() {
        let path = UsageCache.defaultPath().path
        XCTAssertTrue(path.contains("Library/Caches/AIUsageMonitor/cache.json"))
    }

    // MARK: - Settings

    func testSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.refreshSeconds, 300)
        XCTAssertEqual(settings.warningThreshold, 50)
        XCTAssertEqual(settings.criticalThreshold, 20)
        XCTAssertTrue(settings.showNotifications)
    }

    func testSettingsRoundTrip() throws {
        let suiteName = "aium-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.refreshSeconds = 600
        settings.warningThreshold = 60
        settings.criticalThreshold = 25
        settings.showNotifications = false
        SettingsStore.save(settings, to: defaults)

        let loaded = SettingsStore.load(from: defaults)
        XCTAssertEqual(loaded, settings)
    }

    func testSettingsLoadFallsBackToDefaultsOnCorruption() {
        let suiteName = "aium-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: "settings")
        XCTAssertEqual(SettingsStore.load(from: defaults), AppSettings())
    }

    // MARK: - Snapshot

    func testSnapshotBuildsFromValues() {
        let values = [
            "commandcode": liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 45),
            "codex": liveUsage(key: "codex", name: "Codex", fiveHour: 10).markingStale(status: .stale, error: "stale"),
            "opencode": ProviderUsage.unavailable(
                providerName: "OpenCode Go", status: .authError, fetchedAt: Date(), error: "missing key"
            ),
        ]
        let settings = AppSettings()
        let result = UsageSnapshot.make(from: values, settings: settings)
        XCTAssertEqual(result.lowestRemainingPercent, 45) // stale codex excluded
        XCTAssertEqual(result.gaugeState, "warning")
        XCTAssertEqual(result.providers.map(\.key), ["codex", "commandcode", "opencode"])
        XCTAssertTrue(result.providers.first { $0.key == "codex" }!.stale)
        XCTAssertEqual(result.providers.first { $0.key == "opencode" }!.windows.count, 0)
    }

    func testSnapshotGaugeStateDegradedWithoutLiveData() {
        let values = [
            "codex": liveUsage(key: "codex", name: "Codex").markingStale(status: .stale, error: "stale"),
        ]
        let result = UsageSnapshot.make(from: values, settings: AppSettings())
        XCTAssertNil(result.lowestRemainingPercent)
        XCTAssertEqual(result.gaugeState, "degraded")
    }

    func testSnapshotJSONRoundTrip() throws {
        let values = [
            "commandcode": liveUsage(key: "commandcode", name: "CommandCode", fiveHour: 45),
        ]
        var snapshot = UsageSnapshot.make(from: values, settings: AppSettings())
        // Whole-second dates survive the ISO-8601 (no fractional) encoding.
        snapshot.savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try JSONEncoder.withISODates().encode(snapshot)
        let decoded = try JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testSnapshotStoreRequiresEntitledAppGroup() throws {
        // A test process has no app-group entitlement, so container creation
        // is denied by containermanagerd; the store must surface the failure
        // instead of pretending a snapshot was published.
        let groupID = "group.com.gmalbert.aiusagemonitor.tests-\(UUID().uuidString)"
        XCTAssertThrowsError(try SnapshotStore.save(
            UsageSnapshot(
                savedAt: Date(),
                refreshSeconds: 300,
                gaugeState: "normal",
                lowestRemainingPercent: 50,
                providers: []
            ),
            to: groupID
        ))
        XCTAssertNil(SnapshotStore.load(from: groupID))
        // The real app-group identifier is only usable by entitled processes.
        if SnapshotStore.containerURL(for: groupID) == nil {
            XCTAssertNil(SnapshotStore.load(from: groupID))
        }
    }

    // MARK: - Keychain

    /// The round-trip test writes to the login keychain, so it is skipped
    /// when the keychain is locked: a write would make securityd display an
    /// unlock prompt on the user's screen.
    private var loginKeychainUnlocked: Bool {
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else { return false }
        var status: UInt32 = 0
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        return status & 0x0001 != 0  // kSecUnlockStateStatus
    }

    func testKeychainRoundTrip() throws {
        try XCTSkipUnless(loginKeychainUnlocked, "login keychain is locked")
        let store = KeychainStore(service: "AIUsageMonitorTests", account: "test-\(UUID().uuidString)")
        XCTAssertNil(store.loadKey())
        try store.saveKey("  secret-key  ")
        XCTAssertEqual(store.loadKey(), "secret-key")
        XCTAssertTrue(store.deleteKey())
        XCTAssertNil(store.loadKey())
        XCTAssertFalse(store.deleteKey())
    }

    func testKeychainRejectsEmptyKey() {
        let store = KeychainStore(service: "AIUsageMonitorTests", account: "test-\(UUID().uuidString)")
        XCTAssertThrowsError(try store.saveKey("   "))
    }
}
