import Foundation

public struct PriceStats: Equatable {
    public let min: PricePoint
    public let max: PricePoint
    public let average: Double
}

public enum PriceMath {
    public static func stats(_ points: [PricePoint]) -> PriceStats? {
        guard let first = points.first else { return nil }
        var lo = first, hi = first, sum = 0.0
        for p in points {
            if p.total < lo.total { lo = p }
            if p.total > hi.total { hi = p }
            sum += p.total
        }
        return PriceStats(min: lo, max: hi, average: sum / Double(points.count))
    }

    /// Start of the cheapest run of `slots` consecutive points (e.g. the best 2 hours to charge).
    public static func cheapestWindow(_ points: [PricePoint], slots: Int) -> (start: PricePoint, average: Double)? {
        guard slots > 0, points.count >= slots else { return nil }
        var best: (Int, Double)?
        var window = points.prefix(slots).reduce(0) { $0 + $1.total }
        best = (0, window / Double(slots))
        if points.count > slots {
            for i in slots..<points.count {
                window += points[i].total - points[i - slots].total
                let avg = window / Double(slots)
                if avg < best!.1 { best = (i - slots + 1, avg) }
            }
        }
        return best.map { (points[$0.0], $0.1) }
    }

    /// Where `value` sits between today's min and max, 0…1 (nil when flat).
    public static func relativePosition(_ value: Double, in stats: PriceStats) -> Double? {
        let span = stats.max.total - stats.min.total
        guard span > 0 else { return nil }
        return (value - stats.min.total) / span
    }
}

/// Decides when the app should talk to Tibber again. Prices change at slot boundaries from the cache;
/// the network is only needed once a day for today and once tomorrow's day-ahead prices are published.
public enum RefreshPolicy {
    /// Local hour after which tomorrow's prices are expected (day-ahead auction results, ~13:00 CET).
    public static let tomorrowAvailableHour = 13
    public static let retryInterval: TimeInterval = 15 * 60
    public static let maxAge: TimeInterval = 6 * 3600

    public enum Reason: Equatable { case noData, todayRolledOver, tomorrowExpected, stale, none }

    public static func reason(data: PriceData?, lastAttempt: Date?, now: Date = Date(), timeZone: TimeZone? = nil) -> Reason {
        guard let data else { return lastAttempt.map { now.timeIntervalSince($0) >= retryInterval } ?? true ? .noData : .none }
        if !data.coversToday(now) { return .todayRolledOver }
        if now.timeIntervalSince(data.fetchedAt) > maxAge { return .stale }
        if !data.hasTomorrow {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone ?? data.timeZone
            if cal.component(.hour, from: now) >= tomorrowAvailableHour,
               (lastAttempt.map { now.timeIntervalSince($0) >= retryInterval } ?? true) {
                return .tomorrowExpected
            }
        }
        return .none
    }
}
