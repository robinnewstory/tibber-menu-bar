import Foundation

/// Finds the cheapest run of consecutive slots that starts at or after a given moment,
/// across today and tomorrow. Durations are expressed in slots so hourly and quarter-hourly data behave alike.
public struct PlannedWindow: Equatable {
    public let start: Date
    public let end: Date
    public let average: Double
    public let slots: Int

    public init(start: Date, end: Date, average: Double, slots: Int) {
        self.start = start; self.end = end; self.average = average; self.slots = slots
    }
}

public enum Planner {
    public static let durationsHours: [Int] = [1, 2, 3, 4, 6]

    /// Cheapest `hours` window among slots starting at or after `from` (the current slot counts as upcoming).
    public static func cheapestWindow(in data: PriceData, hours: Int, from now: Date) -> PlannedWindow? {
        let slotLength = data.resolution.slotLength
        let slots = max(1, Int((Double(hours) * 3600 / slotLength).rounded()))
        let upcoming = data.all.filter { $0.startsAt.addingTimeInterval(slotLength) > now }
        guard let best = PriceMath.cheapestWindow(upcoming, slots: slots) else { return nil }
        return PlannedWindow(start: best.start.startsAt, end: best.start.startsAt.addingTimeInterval(Double(slots) * slotLength), average: best.average, slots: slots)
    }
}

/// Direction of the next slot relative to the current one, for the menu bar arrow.
public enum Trend: Equatable {
    case up, down, flat

    /// Changes smaller than `tolerance` (fraction of the current price) count as flat.
    public static func between(current: PricePoint?, next: PricePoint?, tolerance: Double = 0.02) -> Trend? {
        guard let current, let next else { return nil }
        guard current.total != 0 else { return next.total > 0 ? .up : (next.total < 0 ? .down : .flat) }
        let change = (next.total - current.total) / abs(current.total)
        if change > tolerance { return .up }
        if change < -tolerance { return .down }
        return .flat
    }

    public var arrow: String {
        switch self {
        case .up: return "↗"
        case .down: return "↘"
        case .flat: return "→"
        }
    }
}

/// Exponential backoff for failed fetches: 1, 2, 4, 8 … minutes, capped.
public enum Backoff {
    public static let base: TimeInterval = 60
    public static let cap: TimeInterval = 30 * 60

    public static func delay(afterFailures n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return min(cap, base * pow(2, Double(min(n, 20) - 1)))
    }

    public static func mayRetry(failures: Int, lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard let lastAttempt, failures > 0 else { return true }
        return now.timeIntervalSince(lastAttempt) >= delay(afterFailures: failures)
    }
}
