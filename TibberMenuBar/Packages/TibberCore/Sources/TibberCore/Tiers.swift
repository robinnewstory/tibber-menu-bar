import Foundation

/// One scale for "how expensive is this slot", from either Tibber's level or today's average.
public enum DisplayTier: String, Codable, Equatable, Sendable {
    case veryCheap, cheap, normal, expensive, veryExpensive

    public var label: String {
        switch self {
        case .veryCheap: return "Very cheap"
        case .cheap: return "Cheap"
        case .normal: return "Normal"
        case .expensive: return "Expensive"
        case .veryExpensive: return "Very expensive"
        }
    }
    public var isCheap: Bool { self == .cheap || self == .veryCheap }
    public var isExpensive: Bool { self == .expensive || self == .veryExpensive }
}

public enum LevelSource: String, Codable, CaseIterable, Sendable {
    case tibber    // Tibber's level, which compares with recent days
    case average   // relative to today's average

    public var label: String {
        switch self {
        case .tibber: return "Tibber's level (vs. recent days)"
        case .average: return "Today's average"
        }
    }
}

public enum TierResolver {
    public static func tier(for point: PricePoint, source: LevelSource, dayAverage: Double?) -> DisplayTier {
        switch source {
        case .tibber:
            switch point.level {
            case .veryCheap?: return .veryCheap
            case .cheap?: return .cheap
            case .expensive?: return .expensive
            case .veryExpensive?: return .veryExpensive
            case .normal?: return .normal
            case nil:
                // Fall back to the average when Tibber sends no level at all.
                guard let dayAverage else { return .normal }
                return tier(for: point, source: .average, dayAverage: dayAverage)
            }
        case .average:
            guard let dayAverage else { return .normal }
            switch PriceMath.relativeTier(point.total, average: dayAverage) {
            case .cheap: return .cheap
            case .expensive: return .expensive
            case .normal: return .normal
            }
        }
    }
}
