import Foundation

/// Minimal GraphQL client for api.tibber.com. Only what the menu bar needs: homes and price info.
public final class TibberClient {
    public static let endpoint = URL(string: "https://api.tibber.com/v1-beta/gql")!
    public static let userAgent = "TibberMenuBar/0.1 (macOS; +https://github.com/newstory)"

    private let token: String
    private let session: URLSession
    private let endpoint: URL

    public init(token: String, session: URLSession = .shared, endpoint: URL = TibberClient.endpoint) {
        self.token = token
        self.session = session
        self.endpoint = endpoint
    }

    // MARK: Queries

    static let homesQuery = """
    { viewer { homes { id appNickname timeZone address { city } currentSubscription { status } } } }
    """

    static func pricesQuery(homeId: String?, resolution: Resolution) -> String {
        let fields = "total energy tax startsAt currency level"
        let selection = "currentSubscription { status priceInfo(resolution: \(resolution.rawValue)) { current { \(fields) } today { \(fields) } tomorrow { \(fields) } } }"
        let home = homeId.map { "home(id: \"\($0)\")" } ?? "homes"
        return "{ viewer { \(home) { id appNickname timeZone address { city } \(selection) } } }"
    }

    public func fetchHomes() async throws -> [HomeInfo] {
        let data: ViewerHomes = try await run(Self.homesQuery)
        return data.viewer.homes.map(Self.homeInfo)
    }

    /// Prices for `homeId`, or for the first home with a subscription when nil.
    public func fetchPrices(homeId: String?, resolution: Resolution, now: Date = Date()) async throws -> PriceData {
        let query = Self.pricesQuery(homeId: homeId, resolution: resolution)
        let homes: [HomeDTO]
        if homeId != nil {
            let data: ViewerHome = try await run(query)
            guard let home = data.viewer.home else { throw TibberError.noHomes }
            homes = [home]
        } else {
            let data: ViewerHomes = try await run(query)
            homes = data.viewer.homes
        }
        guard !homes.isEmpty else { throw TibberError.noHomes }
        guard let home = homes.first(where: { $0.currentSubscription?.priceInfo != nil }) ?? homes.first else { throw TibberError.noHomes }
        guard let info = home.currentSubscription?.priceInfo else { throw TibberError.noSubscription(Self.homeInfo(home).displayName) }
        return try Self.priceData(home: home, info: info, resolution: resolution, fetchedAt: now)
    }

    // MARK: Transport

    private func run<T: Decodable>(_ query: String) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw TibberError.invalidToken }
        guard (200...299).contains(status) else { throw TibberError.http(status) }
        let envelope: GQLEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(GQLEnvelope<T>.self, from: data)
        } catch {
            throw TibberError.decoding(error.localizedDescription)
        }
        if let errors = envelope.errors, !errors.isEmpty {
            if errors.contains(where: { $0.extensions?.code == "UNAUTHENTICATED" || $0.message.lowercased().contains("invalid token") }) {
                throw TibberError.invalidToken
            }
            if envelope.data == nil { throw TibberError.graphQL(errors.map(\.message).joined(separator: "; ")) }
        }
        guard let payload = envelope.data else { throw TibberError.decoding("empty data") }
        return payload
    }

    // MARK: Mapping

    static func homeInfo(_ h: HomeDTO) -> HomeInfo {
        HomeInfo(id: h.id, nickname: h.appNickname, timeZone: h.timeZone ?? TimeZone.current.identifier,
                 city: h.address?.city, hasSubscription: h.currentSubscription != nil)
    }

    static func priceData(home: HomeDTO, info: PriceInfoDTO, resolution: Resolution, fetchedAt: Date) throws -> PriceData {
        func point(_ p: PriceDTO) throws -> PricePoint {
            guard let date = DateParsing.parse(p.startsAt) else { throw TibberError.decoding("bad startsAt \(p.startsAt)") }
            return PricePoint(startsAt: date, total: p.total, energy: p.energy, tax: p.tax, level: p.level.flatMap(PriceLevel.init(rawValue:)), currency: p.currency)
        }
        return PriceData(home: homeInfo(home), resolution: resolution,
                         today: try info.today.map(point), tomorrow: try info.tomorrow.map(point), fetchedAt: fetchedAt)
    }
}

// MARK: - DTOs

struct GQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GQLError]?
}
struct GQLError: Decodable {
    struct Extensions: Decodable { let code: String? }
    let message: String
    let extensions: Extensions?
}
struct ViewerHomes: Decodable { let viewer: HomesViewer }
struct HomesViewer: Decodable { let homes: [HomeDTO] }
struct ViewerHome: Decodable { let viewer: HomeViewer }
struct HomeViewer: Decodable { let home: HomeDTO? }
struct HomeDTO: Decodable {
    let id: String
    let appNickname: String?
    let timeZone: String?
    let address: AddressDTO?
    let currentSubscription: SubscriptionDTO?
}
struct AddressDTO: Decodable { let city: String? }
struct SubscriptionDTO: Decodable {
    let status: String?
    let priceInfo: PriceInfoDTO?
}
struct PriceInfoDTO: Decodable {
    let current: PriceDTO?
    let today: [PriceDTO]
    let tomorrow: [PriceDTO]
}
struct PriceDTO: Decodable {
    let total: Double
    let energy: Double?
    let tax: Double?
    let startsAt: String
    let currency: String
    let level: String?
}

/// Tibber timestamps look like "2025-10-01T00:00:00.000+02:00"; be lenient about fractional seconds.
public enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    public static func parse(_ s: String) -> Date? { withFraction.date(from: s) ?? plain.date(from: s) }
}
