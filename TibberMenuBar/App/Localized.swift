import Foundation
import TibberCore

// Presentation strings for values that live in TibberCore. The core stays free of localization;
// the app owns every user-facing sentence so the String Catalog covers all of them.

extension DisplayTier {
    var localizedLabel: String {
        switch self {
        case .veryCheap: return String(localized: "Very cheap")
        case .cheap: return String(localized: "Cheap")
        case .normal: return String(localized: "Normal")
        case .expensive: return String(localized: "Expensive")
        case .veryExpensive: return String(localized: "Very expensive")
        }
    }
}

extension Resolution {
    var localizedLabel: String {
        self == .hourly ? String(localized: "Hourly") : String(localized: "15 minutes")
    }
}

extension LabelStyle {
    var localizedLabel: String {
        switch self {
        case .cents: return String(localized: "Cents, one decimal (28,3¢)")
        case .centsWhole: return String(localized: "Cents, whole (28¢)")
        case .currency: return String(localized: "Currency (€ 0,28)")
        case .currency3: return String(localized: "Currency, three decimals (€ 0,283)")
        case .plain: return String(localized: "Plain (0,283)")
        }
    }
}

/// User-facing wording for errors, in the user's language.
enum ErrorText {
    static func describe(_ error: Error) -> String {
        guard let tibber = error as? TibberError else { return error.localizedDescription }
        switch tibber {
        case .noToken: return String(localized: "No Tibber access token yet. Add one in Settings.")
        case .invalidToken: return String(localized: "Tibber rejected the access token. Create a new one at developer.tibber.com.")
        case .malformedToken(let detail):
            return String(localized: "That doesn't look like a complete Tibber access token (\(detail)). Copy the whole token from developer.tibber.com → Settings → Access Token and paste it again.")
        case .http(let code): return String(localized: "Tibber responded with HTTP \(code).")
        case .graphQL(let message): return String(localized: "Tibber API: \(message)")
        case .noHomes: return String(localized: "No homes on this Tibber account.")
        case .noSubscription(let home): return String(localized: "\(home) has no active Tibber subscription, so there are no prices.")
        case .decoding(let why): return String(localized: "Unexpected response from Tibber: \(why)")
        }
    }
}

/// Title and body for each price event.
enum NotificationText {
    static func text(for event: PriceEvent, timeZone: TimeZone, style: LabelStyle) -> (title: String, body: String) {
        func price(_ v: Double, _ currency: String) -> String { PriceFormatter.menuBar(v, currency: currency, style: style) }
        func time(_ d: Date) -> String { PriceFormatter.time(d, timeZone: timeZone) }
        switch event {
        case .tomorrowPublished(let low, let high, let avg, let currency):
            return (String(localized: "Tomorrow's prices are in"),
                    String(localized: "Low \(price(low, currency)), average \(price(avg, currency)), high \(price(high, currency))."))
        case .cheapWindowStarts(let w, let currency):
            return (String(localized: "Cheap \(w.hoursText) h window starts \(time(w.start))"),
                    String(localized: "Until \(time(w.end)), average \(price(w.average, currency))."))
        case .belowThreshold(let p, let threshold, let currency):
            return (String(localized: "Price dropped below \(price(threshold, currency))"), String(localized: "Now \(price(p, currency))."))
        case .aboveThreshold(let p, let threshold, let currency):
            return (String(localized: "Price rose above \(price(threshold, currency))"), String(localized: "Now \(price(p, currency))."))
        }
    }
}
