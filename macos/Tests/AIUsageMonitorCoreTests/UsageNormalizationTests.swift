import XCTest
@testable import AIUsageMonitorCore

final class UsageNormalizationTests: XCTestCase {
    func testZeroCapIsRejected() {
        XCTAssertThrowsError(try windowFromUsedAndCap("Weekly", used: 0, cap: 0, resetAt: 1_700_000_000_000)) { error in
            XCTAssertTrue(error is SchemaError)
        }
    }

    func testInvalidISOIsRejected() {
        XCTAssertThrowsError(try localFromISO("not-a-time")) { error in
            XCTAssertTrue(error is SchemaError)
        }
    }

    func testISOWithoutTimezoneIsRejected() {
        XCTAssertThrowsError(try localFromISO("2026-09-19T20:15:29"))
    }

    func testUnixNormalizerAcceptsProviderISOTimestamp() {
        let window = try! windowFromUsedAndCap("Monthly", used: 1, cap: 10, resetAt: "2026-09-19T20:15:29.000Z")
        XCTAssertNotNil(window.resetAt)
    }

    func testUnixMillisecondsAreDetected() {
        let date = try! localFromUnix(1_700_000_000_000)
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
    }

    func testUnixSecondsAreDetected() {
        let date = try! localFromUnix(1_700_000_000)
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
    }

    func testNumericStringTimestampIsAccepted() {
        let date = try! localFromUnix("1794767396")
        XCTAssertEqual(date.timeIntervalSince1970, 1_794_767_396, accuracy: 1)
    }

    func testBoolIsRejectedAsNumber() {
        XCTAssertThrowsError(try number(true, "field")) { error in
            XCTAssertTrue(error is SchemaError)
            XCTAssertEqual((error as! SchemaError).message, "field must be a number")
        }
    }

    func testPercentRejectsOutOfRangeValues() {
        XCTAssertThrowsError(try percent(101, "field"))
        XCTAssertThrowsError(try percent(-1, "field"))
        XCTAssertEqual(try! percent(86, "field"), 86)
    }

    func testWindowFromUsedAndCapClamps() {
        let over = try! windowFromUsedAndCap("5-hour", used: 20, cap: 10, resetAt: 1_700_000_000_000)
        XCTAssertEqual(over.usedPercent, 100)
        XCTAssertEqual(over.remainingPercent, 0)
        XCTAssertEqual(over.remaining, -10)
        let under = try! windowFromUsedAndCap("5-hour", used: -5, cap: 10, resetAt: 1_700_000_000_000)
        XCTAssertEqual(under.usedPercent, 0)
        XCTAssertEqual(under.remainingPercent, 100)
    }

    func testWindowFromUsedAndCapRequiresResetTimestamp() {
        XCTAssertThrowsError(try windowFromUsedAndCap("5-hour", used: 1, cap: 10, resetAt: nil)) { error in
            XCTAssertTrue(error is SchemaError)
        }
    }

    func testRelativeCountdownUsesDaysAndHours() {
        let now = Date()
        XCTAssertEqual(relativeCountdown(to: now.addingTimeInterval(5 * 86_400 + 10 * 3_600), from: now), "in 5d 10h")
        XCTAssertEqual(relativeCountdown(to: now.addingTimeInterval(5 * 86_400), from: now), "in 5d")
        XCTAssertEqual(relativeCountdown(to: now.addingTimeInterval(2 * 3_600 + 44 * 60), from: now), "in 2h 44m")
        XCTAssertEqual(relativeCountdown(to: now.addingTimeInterval(44 * 60), from: now), "in 44m")
        XCTAssertEqual(relativeCountdown(to: now.addingTimeInterval(-60), from: now), "in 0m")
    }

    func testFormatLocalTimeContainsVerbAndCountdown() {
        let date = Date().addingTimeInterval(2 * 3_600 + 5 * 60)
        let rendered = formatLocalTime(date, verb: "Resets")
        XCTAssertTrue(rendered.hasPrefix("Resets"))
        XCTAssertTrue(rendered.contains("in 2h"))
    }

    func testRelativeAge() {
        let now = Date()
        XCTAssertEqual(relativeAge(since: now.addingTimeInterval(-0.4), from: now), "0s ago")
        XCTAssertEqual(relativeAge(since: now.addingTimeInterval(-30), from: now), "30s ago")
        XCTAssertEqual(relativeAge(since: now.addingTimeInterval(-120), from: now), "2m ago")
        XCTAssertEqual(relativeAge(since: now.addingTimeInterval(-3 * 3_600), from: now), "3h ago")
    }
}
