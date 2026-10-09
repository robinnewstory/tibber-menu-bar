import XCTest
@testable import TibberCore

final class ParsingTests: XCTestCase {
    func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "prices", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testDecodesQuarterHourlyDay() throws {
        let env = try JSONDecoder().decode(GQLEnvelope<ViewerHomes>.self, from: try fixture())
        let home = try XCTUnwrap(env.data?.viewer.homes.first)
        let data = try TibberClient.priceData(home: home, info: try XCTUnwrap(home.currentSubscription?.priceInfo), resolution: .quarterHourly, fetchedAt: Date())
        XCTAssertEqual(data.today.count, 96)
        XCTAssertEqual(data.tomorrow.count, 0)
        XCTAssertEqual(data.home.displayName, "Thuis")
        XCTAssertEqual(data.timeZone.identifier, "Europe/Amsterdam")
        XCTAssertEqual(data.today.first?.startsAt, DateParsing.parse("2026-10-08T00:00:00+02:00"))
        XCTAssertEqual(data.today[1].startsAt.timeIntervalSince(data.today[0].startsAt), 900)
        let at = try XCTUnwrap(DateParsing.parse("2026-10-08T14:07:00+02:00"))
        let current = try XCTUnwrap(data.current(at: at))
        XCTAssertEqual(current.startsAt, DateParsing.parse("2026-10-08T14:00:00+02:00"))
        XCTAssertEqual(data.next(after: at)?.startsAt, DateParsing.parse("2026-10-08T14:15:00+02:00"))
        XCTAssertTrue(data.coversToday(at))
        XCTAssertFalse(data.coversToday(at.addingTimeInterval(86400)))
    }

    func testDateParsingVariants() {
        XCTAssertNotNil(DateParsing.parse("2025-10-01T00:00:00.000+02:00"))
        XCTAssertNotNil(DateParsing.parse("2025-10-01T00:00:00+02:00"))
        XCTAssertNotNil(DateParsing.parse("2025-10-01T00:00:00Z"))
        XCTAssertNil(DateParsing.parse("yesterday"))
    }

    func testQueryShape() {
        let q = TibberClient.pricesQuery(homeId: "abc", resolution: .quarterHourly)
        XCTAssertTrue(q.contains("home(id: \"abc\")"))
        XCTAssertTrue(q.contains("priceInfo(resolution: QUARTER_HOURLY)"))
        XCTAssertTrue(TibberClient.pricesQuery(homeId: nil, resolution: .hourly).contains("homes {"))
    }

    func testInvalidTokenDetection() async throws {
        // A 200 with a GraphQL UNAUTHENTICATED error is how Tibber reports a bad token.
        let body = #"{"errors":[{"message":"invalid token","locations":[],"path":["viewer"],"extensions":{"code":"UNAUTHENTICATED"}}],"data":null}"#
        let session = StubSession.session(status: 200, body: body)
        let client = TibberClient(token: "bad", session: session, endpoint: URL(string: "https://stub.local/gql")!)
        do {
            _ = try await client.fetchHomes()
            XCTFail("expected invalidToken")
        } catch let error as TibberError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    func testFetchPricesThroughStubbedTransport() async throws {
        let session = StubSession.session(status: 200, body: String(decoding: try fixture(), as: UTF8.self))
        let client = TibberClient(token: "ok", session: session, endpoint: URL(string: "https://stub.local/gql")!)
        let data = try await client.fetchPrices(homeId: nil, resolution: .quarterHourly)
        XCTAssertEqual(data.today.count, 96)
        XCTAssertEqual(StubSession.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ok")
        XCTAssertNotNil(StubSession.lastRequest?.value(forHTTPHeaderField: "User-Agent"))
    }
}

final class MathAndPolicyTests: XCTestCase {
    func points(_ totals: [Double]) -> [PricePoint] {
        totals.enumerated().map { PricePoint(startsAt: Date(timeIntervalSince1970: 1_800_000_000 + Double($0.offset) * 900), total: $0.element, currency: "EUR") }
    }

    func testStatsAndCheapestWindow() throws {
        let p = points([0.30, 0.20, 0.10, 0.12, 0.40, 0.11])
        let s = try XCTUnwrap(PriceMath.stats(p))
        XCTAssertEqual(s.min.total, 0.10)
        XCTAssertEqual(s.max.total, 0.40)
        XCTAssertEqual(s.average, 0.205, accuracy: 0.0001)
        let w = try XCTUnwrap(PriceMath.cheapestWindow(p, slots: 2))
        XCTAssertEqual(w.start, p[2])
        XCTAssertEqual(w.average, 0.11, accuracy: 0.0001)
        XCTAssertNil(PriceMath.cheapestWindow(p, slots: 10))
        XCTAssertEqual(PriceMath.relativePosition(0.25, in: s)!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(PriceMath.relativeTier(0.18, average: 0.246), .cheap)
        XCTAssertEqual(PriceMath.relativeTier(0.25, average: 0.246), .normal)
        XCTAssertEqual(PriceMath.relativeTier(0.34, average: 0.246), .expensive)
    }

    func testRefreshPolicy() throws {
        let tz = TimeZone(identifier: "Europe/Amsterdam")!
        let home = HomeInfo(id: "h", nickname: nil, timeZone: tz.identifier, city: nil, hasSubscription: true)
        let dayStart = try XCTUnwrap(DateParsing.parse("2026-10-08T00:00:00+02:00"))
        let today = (0..<96).map { PricePoint(startsAt: dayStart.addingTimeInterval(Double($0) * 900), total: 0.2, currency: "EUR") }
        let morning = try XCTUnwrap(DateParsing.parse("2026-10-08T09:00:00+02:00"))
        let afternoon = try XCTUnwrap(DateParsing.parse("2026-10-08T13:05:00+02:00"))
        let data = PriceData(home: home, resolution: .quarterHourly, today: today, tomorrow: [], fetchedAt: morning)

        XCTAssertEqual(RefreshPolicy.reason(data: nil, lastAttempt: nil, now: morning), .noData)
        XCTAssertEqual(RefreshPolicy.reason(data: nil, lastAttempt: morning.addingTimeInterval(-60), now: morning), .none)
        XCTAssertEqual(RefreshPolicy.reason(data: data, lastAttempt: morning, now: morning.addingTimeInterval(3600)), .none)
        XCTAssertEqual(RefreshPolicy.reason(data: data, lastAttempt: morning, now: afternoon), .tomorrowExpected)
        XCTAssertEqual(RefreshPolicy.reason(data: data, lastAttempt: afternoon, now: afternoon.addingTimeInterval(5 * 60)), .none)
        XCTAssertEqual(RefreshPolicy.reason(data: data, lastAttempt: afternoon, now: afternoon.addingTimeInterval(16 * 60)), .tomorrowExpected)
        let withTomorrow = PriceData(home: home, resolution: .quarterHourly, today: today, tomorrow: today.map { PricePoint(startsAt: $0.startsAt.addingTimeInterval(86400), total: 0.2, currency: "EUR") }, fetchedAt: afternoon)
        XCTAssertEqual(RefreshPolicy.reason(data: withTomorrow, lastAttempt: afternoon, now: afternoon.addingTimeInterval(3600)), .none)
        XCTAssertEqual(RefreshPolicy.reason(data: withTomorrow, lastAttempt: afternoon, now: afternoon.addingTimeInterval(7 * 3600)), .stale)
        let nextDay = try XCTUnwrap(DateParsing.parse("2026-10-09T00:01:00+02:00"))
        XCTAssertEqual(RefreshPolicy.reason(data: data, lastAttempt: afternoon, now: nextDay), .todayRolledOver)
    }

    func testFormatting() {
        let nl = Locale(identifier: "nl_NL")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .cents, locale: en), "28.3¢")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .cents, locale: nl), "28,3¢")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .currency, locale: en), "€0.28")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .plain, locale: en), "0.283")
        XCTAssertEqual(PriceFormatter.menuBar(1.234, currency: "NOK", style: .cents, locale: en), "123.4 øre")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .centsWhole, locale: en), "28¢")
        XCTAssertEqual(PriceFormatter.menuBar(0.2834, currency: "EUR", style: .currency3, locale: en), "€0.283")
        let tz = TimeZone(identifier: "Europe/Amsterdam")!
        let p = PricePoint(startsAt: DateParsing.parse("2026-10-08T14:15:00+02:00")!, total: 0.2, currency: "EUR")
        XCTAssertEqual(PriceFormatter.slotRange(p, slotLength: 900, timeZone: tz, locale: en), "14:15–14:30")
    }

    func testTokenStoreAndCacheRoundTrip() throws {
        var backing: String?
        let store = TokenStore(read: { backing }, write: { backing = $0 })
        XCTAssertNil(try store.load())
        try store.save("  abc \n")
        XCTAssertEqual(try store.load(), "abc")
        try store.save(nil)
        XCTAssertNil(try store.load())

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tibber-\(UUID().uuidString)")
        let cache = PriceCache(directory: dir)
        XCTAssertNil(cache.load())
        let home = HomeInfo(id: "h", nickname: "Thuis", timeZone: "Europe/Amsterdam", city: nil, hasSubscription: true)
        let data = PriceData(home: home, resolution: .hourly, today: points([0.1, 0.2]), tomorrow: [], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        cache.save(data)
        XCTAssertEqual(cache.load(), data)
        try? FileManager.default.removeItem(at: dir)
    }
}

/// URLProtocol stub so the client can be exercised without the network.
final class StubSession: URLProtocol {
    static var status = 200
    static var body = ""
    static var lastRequest: URLRequest?

    static func session(status: Int, body: String) -> URLSession {
        Self.status = status
        Self.body = body
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSession.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PlannerAndRulesTests: XCTestCase {
    func day(_ totals: [Double], start: String) throws -> [PricePoint] {
        let s = try XCTUnwrap(DateParsing.parse(start))
        return totals.enumerated().map { PricePoint(startsAt: s.addingTimeInterval(Double($0.offset) * 3600), total: $0.element, currency: "EUR") }
    }
    let home = HomeInfo(id: "h", nickname: "Thuis", timeZone: "Europe/Amsterdam", city: nil, hasSubscription: true)

    func testPlannerSearchesFromNowAcrossBothDays() throws {
        let today = try day(Array(repeating: 0.30, count: 22) + [0.10, 0.10], start: "2026-10-09T00:00:00+02:00")
        let tomorrow = try day([0.05, 0.05] + Array(repeating: 0.30, count: 22), start: "2026-10-10T00:00:00+02:00")
        let data = PriceData(home: home, resolution: .hourly, today: today, tomorrow: tomorrow, fetchedAt: Date())
        let now = try XCTUnwrap(DateParsing.parse("2026-10-09T09:30:00+02:00"))
        let w = try XCTUnwrap(Planner.cheapestWindow(in: data, hours: 2, from: now))
        XCTAssertEqual(w.start, DateParsing.parse("2026-10-10T00:00:00+02:00"))
        XCTAssertEqual(w.average, 0.05, accuracy: 0.0001)
        // a window may not start in the past, but the running slot still counts
        let late = try XCTUnwrap(DateParsing.parse("2026-10-09T22:30:00+02:00"))
        let w2 = try XCTUnwrap(Planner.cheapestWindow(in: data, hours: 2, from: late))
        XCTAssertEqual(w2.start, DateParsing.parse("2026-10-10T00:00:00+02:00"))
        XCTAssertNil(Planner.cheapestWindow(in: data, hours: 48, from: now))
    }

    func testTrendAndBackoff() {
        let a = PricePoint(startsAt: Date(), total: 0.30, currency: "EUR")
        XCTAssertEqual(Trend.between(current: a, next: PricePoint(startsAt: Date(), total: 0.32, currency: "EUR")), .up)
        XCTAssertEqual(Trend.between(current: a, next: PricePoint(startsAt: Date(), total: 0.25, currency: "EUR")), .down)
        XCTAssertEqual(Trend.between(current: a, next: PricePoint(startsAt: Date(), total: 0.303, currency: "EUR")), .flat)
        XCTAssertNil(Trend.between(current: a, next: nil))
        XCTAssertEqual(Backoff.delay(afterFailures: 0), 0)
        XCTAssertEqual(Backoff.delay(afterFailures: 1), 60)
        XCTAssertEqual(Backoff.delay(afterFailures: 4), 480)
        XCTAssertEqual(Backoff.delay(afterFailures: 12), 1800)
        let now = Date()
        XCTAssertFalse(Backoff.mayRetry(failures: 2, lastAttempt: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(Backoff.mayRetry(failures: 2, lastAttempt: now.addingTimeInterval(-121), now: now))
        XCTAssertTrue(Backoff.mayRetry(failures: 0, lastAttempt: now, now: now))
    }

    func testNotificationRules() throws {
        let today = try day(Array(repeating: 0.30, count: 24), start: "2026-10-09T00:00:00+02:00")
        var tomorrow = try day(Array(repeating: 0.20, count: 24), start: "2026-10-10T00:00:00+02:00")
        tomorrow[3] = PricePoint(startsAt: tomorrow[3].startsAt, total: 0.05, currency: "EUR")
        tomorrow[4] = PricePoint(startsAt: tomorrow[4].startsAt, total: 0.05, currency: "EUR")
        let data = PriceData(home: home, resolution: .hourly, today: today, tomorrow: tomorrow, fetchedAt: Date())
        var state = NotificationState()
        let prefs = NotificationPrefs(cheapWindowStart: true, plannerHours: 2, belowCents: 10, aboveCents: 35, tomorrowPublished: true)

        // 1. tomorrow announced once
        let now1 = try XCTUnwrap(DateParsing.parse("2026-10-09T13:05:00+02:00"))
        var events = NotificationRules.events(data: data, prefs: prefs, state: &state, now: now1)
        XCTAssertEqual(events.count, 1)
        guard case .tomorrowPublished(let low, let high, _, _) = events[0] else { return XCTFail("expected tomorrowPublished") }
        XCTAssertEqual(low, 0.05); XCTAssertEqual(high, 0.20)
        XCTAssertEqual(state.thresholdZone, 0, "first threshold evaluation sets the zone silently")
        events = NotificationRules.events(data: data, prefs: prefs, state: &state, now: now1)
        XCTAssertTrue(events.isEmpty, "nothing repeats")

        // 2. cheap window announced in the 10 minutes before it starts, once
        let before = try XCTUnwrap(DateParsing.parse("2026-10-10T02:52:00+02:00"))
        events = NotificationRules.events(data: data, prefs: prefs, state: &state, now: before)
        guard case .cheapWindowStarts(let w, _)? = events.first else { return XCTFail("expected cheapWindowStarts, got \(events)") }
        XCTAssertEqual(w.start, DateParsing.parse("2026-10-10T03:00:00+02:00"))
        XCTAssertTrue(NotificationRules.events(data: data, prefs: prefs, state: &state, now: before.addingTimeInterval(60)).isEmpty)

        // 3. threshold crossing announced on the transition only
        let inWindow = try XCTUnwrap(DateParsing.parse("2026-10-10T03:10:00+02:00"))
        events = NotificationRules.events(data: data, prefs: prefs, state: &state, now: inWindow)
        XCTAssertEqual(events, [.belowThreshold(price: 0.05, threshold: 0.10, currency: "EUR")])
        XCTAssertTrue(NotificationRules.events(data: data, prefs: prefs, state: &state, now: inWindow.addingTimeInterval(60)).isEmpty)

        XCTAssertEqual(w.hoursText, "2")
    }

    func testLiveProtocolParsing() throws {
        XCTAssertEqual(LiveProtocol.parse(#"{"type":"connection_ack"}"#), .ack)
        XCTAssertEqual(LiveProtocol.parse(#"{"type":"ping"}"#), .ping)
        XCTAssertEqual(LiveProtocol.parse(#"{"id":"1","type":"error","payload":[{"message":"unauthorized"}]}"#), .error("unauthorized"))
        let next = #"{"id":"1","type":"next","payload":{"data":{"liveMeasurement":{"timestamp":"2026-10-09T09:12:34.000+02:00","power":1834,"accumulatedConsumption":7.41,"accumulatedCost":1.92,"currency":"EUR","powerProduction":0,"minPower":120,"averagePower":640.5,"maxPower":4210}}}}"#
        guard case .measurement(let m) = LiveProtocol.parse(next) else { return XCTFail("expected measurement") }
        XCTAssertEqual(m.power, 1834)
        XCTAssertEqual(m.accumulatedConsumption, 7.41)
        XCTAssertEqual(m.accumulatedCost, 1.92)
        XCTAssertEqual(m.timestamp, DateParsing.parse("2026-10-09T09:12:34+02:00"))
        XCTAssertEqual(LiveMeasurement.formatPower(1834, locale: Locale(identifier: "en_US")), "1.8 kW")
        XCTAssertEqual(LiveMeasurement.formatPower(640.4, locale: Locale(identifier: "en_US")), "640 W")
        XCTAssertTrue(LiveProtocol.subscribe(homeId: "abc").contains("liveMeasurement(homeId: \\\"abc\\\")"))
        XCTAssertTrue(LiveProtocol.connectionInit(token: "t").contains("connection_init"))
    }
}

final class TierTests: XCTestCase {
    func testTierResolver() {
        let cheapByTibber = PricePoint(startsAt: Date(), total: 0.30, level: .cheap, currency: "EUR")
        XCTAssertEqual(TierResolver.tier(for: cheapByTibber, source: .tibber, dayAverage: 0.246), .cheap)
        XCTAssertEqual(TierResolver.tier(for: cheapByTibber, source: .average, dayAverage: 0.246), .expensive)
        let noLevel = PricePoint(startsAt: Date(), total: 0.18, level: nil, currency: "EUR")
        XCTAssertEqual(TierResolver.tier(for: noLevel, source: .tibber, dayAverage: 0.246), .cheap, "falls back to the average without a Tibber level")
        XCTAssertEqual(TierResolver.tier(for: noLevel, source: .tibber, dayAverage: nil), .normal)
        XCTAssertTrue(DisplayTier.veryCheap.isCheap)
        XCTAssertTrue(DisplayTier.veryExpensive.isExpensive)
    }
}

final class OddDayTests: XCTestCase {
    let home = HomeInfo(id: "h", nickname: "Thuis", timeZone: "Europe/Amsterdam", city: nil, hasSubscription: true)

    /// 25 October 2026 is the autumn switch in Europe/Amsterdam: 25 hours, 100 quarter-hour slots.
    func testDaylightSavingDayHas100Slots() throws {
        let start = try XCTUnwrap(DateParsing.parse("2026-10-25T00:00:00+02:00"))
        let end = try XCTUnwrap(DateParsing.parse("2026-10-26T00:00:00+01:00"))
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3600)
        let slots = stride(from: 0.0, to: end.timeIntervalSince(start), by: 900).map { PricePoint(startsAt: start.addingTimeInterval($0), total: 0.2, currency: "EUR") }
        XCTAssertEqual(slots.count, 100)
        let data = PriceData(home: home, resolution: .quarterHourly, today: slots, tomorrow: [], fetchedAt: start)
        // the repeated 02:00-03:00 hour still resolves to one slot per instant
        let inRepeatedHour = try XCTUnwrap(DateParsing.parse("2026-10-25T02:30:00+01:00"))
        XCTAssertEqual(data.current(at: inRepeatedHour)?.startsAt, DateParsing.parse("2026-10-25T02:30:00+01:00"))
        XCTAssertTrue(data.coversToday(inRepeatedHour))
        XCTAssertEqual(Planner.cheapestWindow(in: data, hours: 2, from: start)?.slots, 8)
        // and the spring day (29 March 2026) has 92
        let s2 = try XCTUnwrap(DateParsing.parse("2026-03-29T00:00:00+01:00"))
        let e2 = try XCTUnwrap(DateParsing.parse("2026-03-30T00:00:00+02:00"))
        XCTAssertEqual(Int(e2.timeIntervalSince(s2) / 900), 92)
    }

    func testNegativePricesFormatAndRank() throws {
        let points = [-0.012, 0.0, 0.05].enumerated().map { PricePoint(startsAt: Date(timeIntervalSince1970: 1_800_000_000 + Double($0.offset) * 3600), total: $0.element, currency: "EUR") }
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(PriceFormatter.menuBar(-0.012, currency: "EUR", style: .cents, locale: en), "-1.2¢")
        XCTAssertEqual(PriceFormatter.menuBar(-0.012, currency: "EUR", style: .currency, locale: en), "-€0.01")
        let stats = try XCTUnwrap(PriceMath.stats(points))
        XCTAssertEqual(stats.min.total, -0.012)
        XCTAssertEqual(PriceMath.cheapestWindow(points, slots: 2)?.start.total, -0.012)
        XCTAssertEqual(Trend.between(current: points[0], next: points[1]), .up)
        XCTAssertEqual(PriceMath.relativeTier(-0.01, average: 0.0), .normal, "a zero average yields no tiers rather than dividing by zero")
    }

    func testOtherCurrencies() {
        let en = Locale(identifier: "en_US")
        // NumberFormatter separates a currency code from the number with a non-breaking space.
        func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: " ") }
        XCTAssertEqual(PriceFormatter.menuBar(0.9876, currency: "NOK", style: .cents, locale: en), "98.8 øre")
        XCTAssertEqual(plain(PriceFormatter.menuBar(0.9876, currency: "SEK", style: .currency, locale: en)), "SEK 0.99")
        XCTAssertEqual(plain(PriceFormatter.detailed(0.9876, currency: "NOK", locale: en)), "NOK 0.988/kWh")
    }
}
