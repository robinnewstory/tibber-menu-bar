import Foundation

public enum PriceLevel: String, Codable, CaseIterable, Sendable {
    case veryCheap = "VERY_CHEAP"
    case cheap = "CHEAP"
    case normal = "NORMAL"
    case expensive = "EXPENSIVE"
    case veryExpensive = "VERY_EXPENSIVE"

    public var label: String {
        switch self {
        case .veryCheap: return "Very cheap"
        case .cheap: return "Cheap"
        case .normal: return "Normal"
        case .expensive: return "Expensive"
        case .veryExpensive: return "Very expensive"
        }
    }
}

public enum Resolution: String, Codable, CaseIterable, Sendable {
    case hourly = "HOURLY"
    case quarterHourly = "QUARTER_HOURLY"

    public var slotLength: TimeInterval { self == .hourly ? 3600 : 900 }
    public var label: String { self == .hourly ? "Hourly" : "15 minutes" }
}

/// One price slot (an hour or a quarter-hour). Prices are per kWh in `currency`.
public struct PricePoint: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { startsAt }
    public let startsAt: Date
    public let total: Double
    public let energy: Double?
    public let tax: Double?
    public let level: PriceLevel?
    public let currency: String

    public init(startsAt: Date, total: Double, energy: Double? = nil, tax: Double? = nil, level: PriceLevel? = nil, currency: String) {
        self.startsAt = startsAt; self.total = total; self.energy = energy; self.tax = tax; self.level = level; self.currency = currency
    }

    public func contains(_ date: Date, slotLength: TimeInterval) -> Bool {
        date >= startsAt && date < startsAt.addingTimeInterval(slotLength)
    }
}

public struct HomeInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let nickname: String?
    public let timeZone: String
    public let city: String?
    public let hasSubscription: Bool

    public init(id: String, nickname: String?, timeZone: String, city: String?, hasSubscription: Bool) {
        self.id = id; self.nickname = nickname; self.timeZone = timeZone; self.city = city; self.hasSubscription = hasSubscription
    }

    public var displayName: String { nickname?.isEmpty == false ? nickname! : (city ?? "Home") }
}

/// Today's and tomorrow's prices for one home, as fetched at `fetchedAt`.
public struct PriceData: Codable, Equatable, Sendable {
    public let home: HomeInfo
    public let resolution: Resolution
    public let today: [PricePoint]
    public let tomorrow: [PricePoint]
    public let fetchedAt: Date

    public init(home: HomeInfo, resolution: Resolution, today: [PricePoint], tomorrow: [PricePoint], fetchedAt: Date) {
        self.home = home; self.resolution = resolution
        self.today = today.sorted { $0.startsAt < $1.startsAt }
        self.tomorrow = tomorrow.sorted { $0.startsAt < $1.startsAt }
        self.fetchedAt = fetchedAt
    }

    public var all: [PricePoint] { today + tomorrow }
    public var currency: String { (today.first ?? tomorrow.first)?.currency ?? "EUR" }
    public var timeZone: TimeZone { TimeZone(identifier: home.timeZone) ?? .current }

    /// The slot that contains `date`, searching today and tomorrow.
    public func current(at date: Date) -> PricePoint? {
        all.last { $0.contains(date, slotLength: resolution.slotLength) }
    }

    /// The slot after the one containing `date`.
    public func next(after date: Date) -> PricePoint? {
        all.first { $0.startsAt > date }
    }

    /// True when `today` describes the calendar day of `date` in the home's time zone.
    public func coversToday(_ date: Date = Date()) -> Bool {
        guard let first = today.first else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.isDate(first.startsAt, inSameDayAs: date)
    }

    public var hasTomorrow: Bool { !tomorrow.isEmpty }
}

public enum TibberError: LocalizedError, Equatable {
    case noToken
    case invalidToken
    case malformedToken(String)
    case http(Int)
    case graphQL(String)
    case noHomes
    case noSubscription(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Tibber access token yet. Add one in Settings."
        case .invalidToken: return "Tibber rejected the access token. Create a new one at developer.tibber.com."
        case .malformedToken(let detail): return "That doesn't look like a complete Tibber access token (\(detail)). Copy the whole token from developer.tibber.com → Settings → Access Token and paste it again."
        case .http(let code): return "Tibber responded with HTTP \(code)."
        case .graphQL(let message): return "Tibber API: \(message)"
        case .noHomes: return "No homes on this Tibber account."
        case .noSubscription(let home): return "\(home) has no active Tibber subscription, so there are no prices."
        case .decoding(let why): return "Unexpected response from Tibber: \(why)"
        }
    }
}
