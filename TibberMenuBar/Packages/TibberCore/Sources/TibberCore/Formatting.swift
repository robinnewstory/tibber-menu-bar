import Foundation

public enum LabelStyle: String, Codable, CaseIterable, Sendable {
    case cents      // "28.3¢" / "28,3 ct"
    case currency   // "€0.28"
    case plain      // "0.283"

    public var label: String {
        switch self {
        case .cents: return "Cents (28.3¢)"
        case .currency: return "Currency (€0.28)"
        case .plain: return "Plain (0.283)"
        }
    }
}

public enum PriceFormatter {
    /// Compact menu bar text.
    public static func menuBar(_ total: Double, currency: String, style: LabelStyle, locale: Locale = .current) -> String {
        switch style {
        case .cents:
            let cents = total * 100
            let f = NumberFormatter()
            f.locale = locale
            f.minimumFractionDigits = 1
            f.maximumFractionDigits = 1
            let number = f.string(from: NSNumber(value: cents)) ?? String(format: "%.1f", cents)
            return "\(number)\(centSymbol(for: currency))"
        case .currency:
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .currency
            f.currencyCode = currency
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            return f.string(from: NSNumber(value: total)) ?? String(format: "%.2f", total)
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
