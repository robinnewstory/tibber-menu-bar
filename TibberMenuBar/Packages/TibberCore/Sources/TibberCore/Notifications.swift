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
            if lead <= windowLeadTime, lead > -data.resolution.slotLength, state.windowNotifiedStart != window.start {
                state.windowNotifiedStart = window.start
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

    /// Title and body for a notification.
    public static func text(for event: PriceEvent, timeZone: TimeZone, style: LabelStyle = .cents) -> (title: String, body: String) {
        switch event {
        case .tomorrowPublished(let low, let high, let avg, let currency):
            return ("Tomorrow's prices are in",
                    "Low \(PriceFormatter.menuBar(low, currency: currency, style: style)), average \(PriceFormatter.menuBar(avg, currency: currency, style: style)), high \(PriceFormatter.menuBar(high, currency: currency, style: style)).")
        case .cheapWindowStarts(let w, let currency):
            return ("Cheap \(w.slotsHours) h window starts \(PriceFormatter.time(w.start, timeZone: timeZone))",
                    "Until \(PriceFormatter.time(w.end, timeZone: timeZone)), average \(PriceFormatter.menuBar(w.average, currency: currency, style: style)).")
        case .belowThreshold(let price, let threshold, let currency):
            return ("Price dropped below \(PriceFormatter.menuBar(threshold, currency: currency, style: style))",
                    "Now \(PriceFormatter.menuBar(price, currency: currency, style: style)).")
        case .aboveThreshold(let price, let threshold, let currency):
            return ("Price rose above \(PriceFormatter.menuBar(threshold, currency: currency, style: style))",
                    "Now \(PriceFormatter.menuBar(price, currency: currency, style: style)).")
        }
    }
}

extension PlannedWindow {
    var slotsHours: String {
        let hours = end.timeIntervalSince(start) / 3600
        return hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }
}
