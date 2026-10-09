import Foundation
import TibberCore

enum Diagnostics {
    static func printStatus() {
        let token = ((try? TokenStore.keychain.load()) ?? nil) ?? ""
        if token.isEmpty {
            print("token: none")
        } else {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            let odd = Set(token.filter { !($0.isASCII && ($0.isLetter || $0.isNumber)) && !"-_.".contains($0) })
            let oddText = odd.isEmpty ? "token-safe characters only" : "unexpected characters: " + odd.map { "\"\($0)\" (U+\(String(format: "%04X", $0.unicodeScalars.first!.value)))" }.joined(separator: " ")
            print("token: present (\(token.count) chars; part lengths \(parts.map { String($0.count) }.joined(separator: "/")); starts with \(token.prefix(3))…; \(oddText))")
        }
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

extension Diagnostics {
    /// Runs the homes query with the stored token and prints the outcome (never the token).
    static func checkToken() {
        guard let token = (try? TokenStore.keychain.load()) ?? nil, !token.isEmpty else { print("token: none"); return }
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let homes = try await TibberClient(token: token).fetchHomes()
                print("OK: \(homes.count) home(s): " + homes.map { "\($0.displayName)\($0.hasSubscription ? "" : " (no subscription)")" }.joined(separator: ", "))
            } catch {
                print("FAILED: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
    }
}
