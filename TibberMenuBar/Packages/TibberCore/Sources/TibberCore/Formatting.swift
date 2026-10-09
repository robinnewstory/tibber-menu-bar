import Foundation

public enum LabelStyle: String, Codable, CaseIterable, Sendable {
    case cents        // "28.3¢"
    case centsWhole   // "28¢"
    case currency     // "€0.28"
    case currency3    // "€0.283"
    case plain        // "0.283"

    public var label: String {
        switch self {
        case .cents: return "Cents, one decimal (28,3¢)"
        case .centsWhole: return "Cents, whole (28¢)"
        case .currency: return "Currency (€ 0,28)"
        case .currency3: return "Currency, three decimals (€ 0,283)"
        case .plain: return "Plain (0,283)"
        }
    }
}

public enum PriceFormatter {
    /// Compact menu bar text.
    public static func menuBar(_ total: Double, currency: String, style: LabelStyle, locale: Locale = .current) -> String {
        switch style {
        case .cents, .centsWhole:
            let cents = total * 100
            let digits = style == .cents ? 1 : 0
            let f = NumberFormatter()
            f.locale = locale
            f.minimumFractionDigits = digits
            f.maximumFractionDigits = digits
            let number = f.string(from: NSNumber(value: cents)) ?? String(format: digits == 1 ? "%.1f" : "%.0f", cents)
            return "\(number)\(centSymbol(for: currency))"
        case .currency, .currency3:
            let digits = style == .currency ? 2 : 3
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .currency
            f.currencyCode = currency
            f.minimumFractionDigits = digits
            f.maximumFractionDigits = digits
            return f.string(from: NSNumber(value: total)) ?? String(format: digits == 2 ? "%.2f" : "%.3f", total)
        case .plain:
            let f = NumberFormatter()
            f.locale = locale
            f.minimumFractionDigits = 3
            f.maximumFractionDigits = 3
            return f.string(from: NSNumber(value: total)) ?? String(format: "%.3f", total)
        }
    }

    /// Detailed text for the popover, e.g. "€ 0,283 /kWh".
    public static func detailed(_ total: Double, currency: String, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = currency
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return (f.string(from: NSNumber(value: total)) ?? String(format: "%.3f", total)) + "/kWh"
    }

    public static func centSymbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "EUR": return "¢"
        case "NOK", "SEK", "DKK": return " øre"
        default: return "¢"
        }
    }

    public static func slotRange(_ point: PricePoint, slotLength: TimeInterval, timeZone: TimeZone, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return "\(f.string(from: point.startsAt))–\(f.string(from: point.startsAt.addingTimeInterval(slotLength)))"
    }

    public static func time(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
