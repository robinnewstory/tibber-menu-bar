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
