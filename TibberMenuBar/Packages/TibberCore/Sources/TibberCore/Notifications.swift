import Foundation

public struct NotificationPrefs: Codable, Equatable {
    public var cheapWindowStart: Bool
    public var plannerHours: Int
    public var belowCents: Double?
    public var aboveCents: Double?
    public var tomorrowPublished: Bool

    public init(cheapWindowStart: Bool = false, plannerHours: Int = 2, belowCents: Double? = nil, aboveCents: Double? = nil, tomorrowPublished: Bool = false) {
        self.cheapWindowStart = cheapWindowStart; self.plannerHours = plannerHours
        self.belowCents = belowCents; self.aboveCents = aboveCents; self.tomorrowPublished = tomorrowPublished
    }

    public var anyEnabled: Bool { cheapWindowStart || belowCents != nil || aboveCents != nil || tomorrowPublished }
}

/// What has already been announced, so the same thing isn't repeated every tick.
public struct NotificationState: Codable, Equatable {
    public var tomorrowNotifiedFor: String?       // "yyyy-MM-dd" of the day announced
    public var windowNotifiedStart: Date?
    /// End of the announced window. While it runs, the planner keeps finding a "new" window that starts at the
    /// next slot (the announced start has passed), so anything starting before this end is the same window.
    public var windowNotifiedEnd: Date?
    public var thresholdZone: Int?                // -1 below, 0 between, 1 above; nil = not yet evaluated

    public init() {}
}

public enum PriceEvent: Equatable {
    case tomorrowPublished(low: Double, high: Double, average: Double, currency: String)
    case cheapWindowStarts(window: PlannedWindow, currency: String)
    case belowThreshold(price: Double, threshold: Double, currency: String)
    case aboveThreshold(price: Double, threshold: Double, currency: String)
}

/// Pure rules: given prices, preferences and what was announced before, which notifications are due now.
public enum NotificationRules {
    public static let windowLeadTime: TimeInterval = 10 * 60

    public static func events(data: PriceData, prefs: NotificationPrefs, state: inout NotificationState, now: Date = Date()) -> [PriceEvent] {
        var out: [PriceEvent] = []
        let currency = data.currency

        if prefs.tomorrowPublished, data.hasTomorrow, let first = data.tomorrow.first, let stats = PriceMath.stats(data.tomorrow) {
            let key = dayKey(first.startsAt, timeZone: data.timeZone)
            if state.tomorrowNotifiedFor != key {
                state.tomorrowNotifiedFor = key
                out.append(.tomorrowPublished(low: stats.min.total, high: stats.max.total, average: stats.average, currency: currency))
            }
        }

        if prefs.cheapWindowStart, let window = Planner.cheapestWindow(in: data, hours: prefs.plannerHours, from: now) {
            let lead = window.start.timeIntervalSince(now)
            let alreadyAnnounced = state.windowNotifiedEnd.map { window.start < $0 } ?? (state.windowNotifiedStart == window.start)
            if lead <= windowLeadTime, lead > -data.resolution.slotLength, !alreadyAnnounced {
                state.windowNotifiedStart = window.start
                state.windowNotifiedEnd = window.end
                out.append(.cheapWindowStarts(window: window, currency: currency))
            }
        }

        if prefs.belowCents != nil || prefs.aboveCents != nil, let current = data.current(at: now) {
            let cents = current.total * 100
            let zone: Int
            if let below = prefs.belowCents, cents < below { zone = -1 }
            else if let above = prefs.aboveCents, cents > above { zone = 1 }
            else { zone = 0 }
            if let previous = state.thresholdZone, previous != zone {
                if zone == -1, let below = prefs.belowCents { out.append(.belowThreshold(price: current.total, threshold: below / 100, currency: currency)) }
                if zone == 1, let above = prefs.aboveCents { out.append(.aboveThreshold(price: current.total, threshold: above / 100, currency: currency)) }
            }
            state.thresholdZone = zone
        }
        return out
    }

    static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

}

public extension PlannedWindow {
    /// Length as "2" or "1.5", for notification titles.
    var hoursText: String {
        let hours = end.timeIntervalSince(start) / 3600
        return hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }
}
