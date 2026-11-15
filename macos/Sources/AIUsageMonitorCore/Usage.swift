/// Normalization helpers shared by provider adapters and UIs.
///
/// Faithful port of `usage.py`: identical validation rules, error text, and
/// output formatting so behavior and tests stay aligned with the reference.
import Foundation

/// A provider response did not satisfy its versioned contract.
public struct SchemaError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

// MARK: - Number and percent validation

/// Rejects `Bool` values exactly like the reference `number()`.
public func number(_ value: Any?, _ field: String) throws -> Double {
    if let decimal = value as? Decimal {
        return (decimal as NSDecimalNumber).doubleValue
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            throw SchemaError("\(field) must be a number")
        }
        return number.doubleValue
    }
    if let string = value as? String {
        // Strings are numbers only when they parse as one; mirrors float().
        if let parsed = Double(string) { return parsed }
    }
    throw SchemaError("\(field) must be a number")
}

public func percent(_ value: Any?, _ field: String) throws -> Double {
    let parsed = try number(value, field)
    guard (0...100).contains(parsed) else {
        throw SchemaError("\(field) must be between 0 and 100")
    }
    return parsed
}

// MARK: - Timestamp parsing

/// Port of `local_from_unix`: accepts unix seconds, unix milliseconds, numeric
/// strings, and ISO-8601 strings. Returns a local-time `Date`.
public func localFromUnix(_ value: Any?, _ field: String = "timestamp") throws -> Date {
    if let string = value as? String, !string.isEmpty, Double(string) == nil {
        return try localFromISO(string, field)
    }
    var seconds = try number(value, field)
    // CommandCode uses milliseconds; Codex uses seconds.
    if seconds > 10_000_000_000 {
        seconds /= 1000
    }
    guard seconds.isFinite, abs(seconds) < 100_000_000_000 else {
        throw SchemaError("\(field) is not a valid timestamp")
    }
    return Date(timeIntervalSince1970: seconds)
}

/// Port of `local_from_iso`: requires a timezone designator.
public func localFromISO(_ value: Any?, _ field: String = "timestamp") throws -> Date {
    guard let string = value as? String else {
        throw SchemaError("\(field) must be an ISO-8601 timestamp")
    }
    if let date = ISO8601.date(from: string) {
        return date
    }
    throw SchemaError("\(field) is not a valid ISO-8601 timestamp")
}

public enum ISO8601 {
    /// Accepts ISO-8601 strings with or without fractional seconds, matching
    /// the range produced by Python's `isoformat()`.
    public static func date(from string: String) -> Date? {
        withFractional.date(from: string) ?? plain.date(from: string)
    }

    public static func string(from date: Date) -> String {
        plain.string(from: date)
    }

    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Window builders

public func windowFromUsedAndCap(_ name: String, used: Any?, cap: Any?, resetAt: Any?) throws -> UsageWindow {
    let usedValue = try number(used, "\(name).used")
    let capValue = try number(cap, "\(name).cap")
    guard capValue > 0 else {
        throw SchemaError("\(name).cap must be greater than zero")
    }
    let usedPercent = max(0, min(100, usedValue / capValue * 100))
    return UsageWindow(
        name: name,
        usedPercent: usedPercent,
        remainingPercent: 100 - usedPercent,
        resetAt: try localFromUnix(resetAt),
        used: usedValue,
        cap: capValue,
        remaining: capValue - usedValue
    )
}

public func windowFromPercent(_ name: String, usedPercent value: Any?, resetAt: Date?) throws -> UsageWindow {
    let used = try percent(value, "\(name).percent")
    return UsageWindow(name: name, usedPercent: used, remainingPercent: 100 - used, resetAt: resetAt)
}

// MARK: - Formatting

public func formatLocalTime(_ value: Date?, verb: String = "Resets") -> String {
    guard let value else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, h:mm a"
    return "\(verb): \(formatter.string(from: value)) · \(relativeCountdown(to: value))"
}

/// "in 5d 10h", "in 2h 44m", "in 44m" — the countdown shape used by the
/// reference implementation, including its clamping at zero.
public func relativeCountdown(to date: Date, from now: Date = Date()) -> String {
    let totalMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let (days, dayRemainder) = totalMinutes.quotientAndRemainder(dividingBy: 24 * 60)
    let (hours, minutes) = dayRemainder.quotientAndRemainder(dividingBy: 60)
    if days > 0 {
        return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
    }
    return hours > 0 ? "in \(hours)h \(minutes)m" : "in \(minutes)m"
}

/// Short age label like "30s ago" used by the detail surfaces.
public func relativeAge(since date: Date, from now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "\(Int(seconds.rounded()))s ago" }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = Int((seconds / 3_600).rounded())
    if hours < 48 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

// MARK: - ISO date coding for Codable round-trips

public enum ISODateCoder {
    public static func encode(_ date: Date) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func decode(_ string: String) throws -> Date {
        if let date = ISO8601.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        guard let date = plain.date(from: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid ISO-8601 date: \(string)"))
        }
        return date
    }
}

public extension JSONEncoder {
    static func withISODates() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(ISODateCoder.encode(date))
        }
        return encoder
    }
}

public extension JSONDecoder {
    static func withISODates() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let string = try container.decode(String.self)
            return try ISODateCoder.decode(string)
        }
        return decoder
    }
}
