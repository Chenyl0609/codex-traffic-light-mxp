import Foundation

public struct QuotaValues: Equatable, Sendable {
    public var fiveHourRemainingPercent: Int
    public var weeklyRemainingPercent: Int

    public init(fiveHourRemainingPercent: Int, weeklyRemainingPercent: Int) {
        self.fiveHourRemainingPercent = min(100, max(0, fiveHourRemainingPercent))
        self.weeklyRemainingPercent = min(100, max(0, weeklyRemainingPercent))
    }

    public var summary: String {
        "\(fiveHourRemainingPercent)/\(weeklyRemainingPercent)"
    }
}

public enum QuotaExtractor {
    private static let fiveHourKeys = ["five_hour_remaining_percent", "fiveHourRemainingPercent"]
    private static let weeklyKeys = ["weekly_remaining_percent", "weeklyRemainingPercent"]
    private static let preferredContainerKeys = ["quota", "rate_limits", "rateLimits"]

    public static func extract(from data: Data) -> QuotaValues? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return extract(from: object)
    }

    public static func extract(from object: Any) -> QuotaValues? {
        if let dictionary = object as? [String: Any] {
            if let values = values(in: dictionary) {
                return values
            }

            for key in preferredContainerKeys {
                if let child = dictionary[key], let values = extract(from: child) {
                    return values
                }
            }

            for key in dictionary.keys.sorted() where !preferredContainerKeys.contains(key) {
                if let child = dictionary[key], let values = extract(from: child) {
                    return values
                }
            }
        }

        if let array = object as? [Any] {
            for child in array {
                if let values = extract(from: child) {
                    return values
                }
            }
        }

        return nil
    }

    private static func values(in dictionary: [String: Any]) -> QuotaValues? {
        guard let fiveHour = firstPercent(in: dictionary, keys: fiveHourKeys),
              let weekly = firstPercent(in: dictionary, keys: weeklyKeys) else {
            return nil
        }
        return QuotaValues(fiveHourRemainingPercent: fiveHour, weeklyRemainingPercent: weekly)
    }

    private static func firstPercent(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key], let percent = percent(from: value) {
                return percent
            }
        }
        return nil
    }

    private static func percent(from value: Any) -> Int? {
        if value is Bool {
            return nil
        }
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? NSNumber {
            return Int(number.doubleValue)
        }
        if let string = value as? String,
           let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(number)
        }
        return nil
    }
}
