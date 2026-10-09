import Foundation
import TibberCore

/// Made-up prices and a made-up Pulse reading for screenshots (`--snapshot`). Nothing here comes from a real account.
enum DemoData {
    static let home = HomeInfo(id: "demo", nickname: "Demo home", timeZone: "Europe/Amsterdam", city: "Amsterdam", hasSubscription: true, liveMeasurements: true)

    static func prices(now: Date = Date()) -> PriceData {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: home.timeZone)!
        let midnight = calendar.startOfDay(for: now)
        let today = day(from: midnight, anchors: [(0, 0.23), (3, 0.20), (6, 0.24), (8, 0.32), (10, 0.26), (13, 0.17), (15, 0.21), (17, 0.30), (18.5, 0.36), (20, 0.31), (22, 0.26), (24, 0.23)], seed: 1)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: midnight)!
        let tomorrow = day(from: tomorrowStart, anchors: [(0, 0.22), (4, 0.18), (7, 0.27), (9, 0.29), (12, 0.14), (14, 0.15), (17, 0.28), (19, 0.33), (21, 0.27), (24, 0.21)], seed: 2)
        return PriceData(home: home, resolution: .quarterHourly, today: today, tomorrow: tomorrow, fetchedAt: now)
    }

    static func live(now: Date = Date()) -> LiveMeasurement {
        LiveMeasurement(timestamp: now, power: 1834, accumulatedConsumption: 7.41, accumulatedCost: 1.92, currency: "EUR",
                        powerProduction: 0, minPower: 120, averagePower: 640, maxPower: 4210)
    }

    /// 96 quarter-hour slots interpolated between (hour, €/kWh) anchors, with a small deterministic wobble.
    private static func day(from start: Date, anchors: [(Double, Double)], seed: Double) -> [PricePoint] {
        let totals: [Double] = (0..<96).map { i in
            let h = Double(i) / 4
            let upper = anchors.firstIndex { $0.0 >= h } ?? anchors.count - 1
            let (h0, p0) = anchors[max(upper - 1, 0)], (h1, p1) = anchors[upper]
            let t = h1 == h0 ? 0 : (h - h0) / (h1 - h0)
            let smooth = p0 + (p1 - p0) * (0.5 - 0.5 * cos(t * .pi))
            return (smooth + 0.008 * sin(h * 1.7 + seed) * 100).rounded() / 100 == 0 ? smooth : (smooth + 0.006 * sin(h * 1.7 + seed))
        }
        let average = totals.reduce(0, +) / Double(totals.count)
        return totals.enumerated().map { i, total in
            let ratio = total / average
            let level: PriceLevel = ratio < 0.75 ? .veryCheap : ratio < 0.9 ? .cheap : ratio > 1.4 ? .veryExpensive : ratio > 1.15 ? .expensive : .normal
            return PricePoint(startsAt: start.addingTimeInterval(Double(i) * 900), total: (total * 10000).rounded() / 10000, level: level, currency: "EUR")
        }
    }
}
