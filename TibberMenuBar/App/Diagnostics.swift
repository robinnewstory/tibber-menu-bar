import Foundation
import TibberCore

enum Diagnostics {
    static func printStatus() {
        let hasToken = ((try? TokenStore.keychain.load()) ?? nil)?.isEmpty == false
        print("token: \(hasToken ? "present" : "none")")
        guard let data = PriceCache().load() else { print("cache: none"); return }
        let f = ISO8601DateFormatter()
        print("home: \(data.home.displayName) (\(data.home.timeZone)), resolution \(data.resolution.rawValue), fetched \(f.string(from: data.fetchedAt))")
        print("today: \(data.today.count) slots, tomorrow: \(data.tomorrow.count) slots, currency \(data.currency)")
        if let c = data.current(at: Date()) {
            print("current: \(PriceFormatter.menuBar(c.total, currency: data.currency, style: .cents)) (\(c.level?.rawValue ?? "-")) from \(f.string(from: c.startsAt))")
        } else {
            print("current: none for now")
        }
        if let s = PriceMath.stats(data.today) {
            print("today low \(s.min.total) at \(f.string(from: s.min.startsAt)), high \(s.max.total) at \(f.string(from: s.max.startsAt)), avg \(String(format: "%.4f", s.average))")
        }
    }
}
