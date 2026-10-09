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
        print("home: \(data.home.displayName) (\(data.home.timeZone)), resolution \(data.resolution.rawValue), fetched \(f.string(from: data.fetchedAt)), live capable: \(data.home.liveMeasurements)")
        print("today: \(data.today.count) slots, tomorrow: \(data.tomorrow.count) slots, currency \(data.currency)")
        if let c = data.current(at: Date()) {
            let trend = Trend.between(current: c, next: data.next(after: c.startsAt))?.arrow ?? ""
            print("current: \(PriceFormatter.menuBar(c.total, currency: data.currency, style: .cents)) \(trend) (\(c.level?.rawValue ?? "-")) from \(f.string(from: c.startsAt))")
        } else {
            print("current: none for now")
        }
        if let s = PriceMath.stats(data.today) {
            print("today low \(s.min.total) at \(f.string(from: s.min.startsAt)), high \(s.max.total) at \(f.string(from: s.max.startsAt)), avg \(String(format: "%.4f", s.average))")
        }
        if let w = Planner.cheapestWindow(in: data, hours: 2, from: Date()) {
            print("cheapest 2 h from \(f.string(from: w.start)) avg \(String(format: "%.4f", w.average))")
        }
        if let rec = LiveSnapshot.read() {
            let live = rec.measurement
            let span = rec.writtenAt.timeIntervalSince(rec.since)
            let rate = span > 0 ? Double(rec.messages) / span * 60 : 0
            print("live: \(LiveMeasurement.formatPower(live.power)) at \(f.string(from: live.timestamp)) (\(Int(Date().timeIntervalSince(live.timestamp))) s ago), today \(live.accumulatedConsumption.map { String(format: "%.2f kWh", $0) } ?? "?"), cost \(live.accumulatedCost.map { String(format: "%.2f", $0) } ?? "?") \(live.currency ?? "")")
            print("live rate: \(rec.messages) readings in \(Int(span)) s ≈ \(String(format: "%.1f", rate)) per minute")
        } else {
            print("live: no reading recorded yet")
        }
    }

    /// Runs the homes query with the stored token and prints the outcome (never the token).
    static func checkToken() {
        guard let token = (try? TokenStore.keychain.load()) ?? nil, !token.isEmpty else { print("token: none"); return }
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let account = try await TibberClient(token: token).fetchAccount()
                print("OK: \(account.homes.count) home(s): " + account.homes.map { "\($0.displayName)\($0.hasSubscription ? "" : " (no subscription)")\($0.liveMeasurements ? " [Pulse]" : "")" }.joined(separator: ", "))
                print("websocket: \(account.websocketURL?.absoluteString ?? "none")")
            } catch {
                print("FAILED: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
    }

    /// Fetches prices for the configured home and updates the cache, like the app would.
    static func fetch() {
        guard let token = (try? TokenStore.keychain.load()) ?? nil, !token.isEmpty else { print("token: none"); return }
        let homeId = UserDefaults.standard.string(forKey: "homeId")
        let resolution = Resolution(rawValue: UserDefaults.standard.string(forKey: "resolution") ?? "") ?? .quarterHourly
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let data = try await TibberClient(token: token).fetchPrices(homeId: homeId, resolution: resolution)
                PriceCache().save(data)
                print("fetched \(data.today.count) + \(data.tomorrow.count) slots for \(data.home.displayName)")
            } catch {
                print("FAILED: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
        printStatus()
    }
}

extension Diagnostics {
    /// Prints today's and tomorrow's prices as JSON (cents, one decimal) with Tibber's level letters, for mockups and debugging.
    static func dumpToday() {
        guard let data = PriceCache().load() else { print("{}"); return }
        func enc(_ ps: [PricePoint]) -> String {
            "[" + ps.map { String(format: "%.1f", $0.total * 100) }.joined(separator: ",") + "]"
        }
        func lv(_ ps: [PricePoint]) -> String { ps.map { String(($0.level?.rawValue.first).map { String($0) } ?? "-") }.joined() }
        print("{\"resolution\":\"\(data.resolution.rawValue)\",\"today\":\(enc(data.today)),\"todayLevels\":\"\(lv(data.today))\",\"tomorrow\":\(enc(data.tomorrow)),\"tomorrowLevels\":\"\(lv(data.tomorrow))\"}")
    }
}
