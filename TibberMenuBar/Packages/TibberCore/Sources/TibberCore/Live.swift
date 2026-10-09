import Foundation

/// One reading from Tibber Pulse (via the GraphQL websocket subscription).
public struct LiveMeasurement: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let power: Double                  // W, current draw
    public let accumulatedConsumption: Double? // kWh since midnight
    public let accumulatedCost: Double?        // in currency since midnight
    public let currency: String?
    public let powerProduction: Double?        // W fed into the grid right now (solar)
    public let minPower: Double?
    public let averagePower: Double?
    public let maxPower: Double?
    public let accumulatedProduction: Double?  // kWh exported since midnight
    public let accumulatedReward: Double?      // in currency since midnight
    public let maxPowerProduction: Double?     // W, today's export peak

    public init(timestamp: Date, power: Double, accumulatedConsumption: Double? = nil, accumulatedCost: Double? = nil, currency: String? = nil,
                powerProduction: Double? = nil, minPower: Double? = nil, averagePower: Double? = nil, maxPower: Double? = nil,
                accumulatedProduction: Double? = nil, accumulatedReward: Double? = nil, maxPowerProduction: Double? = nil) {
        self.timestamp = timestamp; self.power = power; self.accumulatedConsumption = accumulatedConsumption; self.accumulatedCost = accumulatedCost
        self.currency = currency; self.powerProduction = powerProduction; self.minPower = minPower; self.averagePower = averagePower; self.maxPower = maxPower
        self.accumulatedProduction = accumulatedProduction; self.accumulatedReward = accumulatedReward; self.maxPowerProduction = maxPowerProduction
    }

    /// Draw from the grid minus export to it: negative while solar exceeds consumption.
    public var netPower: Double { power - (powerProduction ?? 0) }
    public var isExporting: Bool { (powerProduction ?? 0) > power }
    public var hasProduction: Bool { (powerProduction ?? 0) > 0 || (accumulatedProduction ?? 0) > 0 }

    public static func formatPower(_ watts: Double, locale: Locale = .current) -> String {
        if abs(watts) >= 1000 {
            let f = NumberFormatter(); f.locale = locale; f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
            return (f.string(from: NSNumber(value: watts / 1000)) ?? String(format: "%.1f", watts / 1000)) + " kW"
        }
        return "\(Int(watts.rounded())) W"
    }
}

/// graphql-transport-ws framing used by Tibber's subscription endpoint.
public enum LiveProtocol {
    public static let subprotocol = "graphql-transport-ws"
    public static let subscriptionId = "1"

    public static func connectionInit(token: String) -> String {
        json(["type": "connection_init", "payload": ["token": token]])
    }

    public static func subscribe(homeId: String) -> String {
        // The home id travels as a GraphQL variable, never spliced into the query text.
        let query = "subscription($homeId: ID!) { liveMeasurement(homeId: $homeId) { timestamp power accumulatedConsumption accumulatedCost currency powerProduction minPower averagePower maxPower accumulatedProduction accumulatedReward maxPowerProduction } }"
        return json(["id": subscriptionId, "type": "subscribe", "payload": ["query": query, "variables": ["homeId": homeId]]])
    }

    public static let pong = json(["type": "pong"])

    public enum Incoming: Equatable {
        case ack
        case ping
        case measurement(LiveMeasurement)
        case error(String)
        case complete
        case other(String)
    }

    public static func parse(_ text: String) -> Incoming {
        guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return .other(text.prefix(80).description) }
        switch type {
        case "connection_ack": return .ack
        case "ping": return .ping
        case "complete": return .complete
        case "error", "connection_error":
            let payload = obj["payload"]
            let message = ((payload as? [[String: Any]])?.first?["message"] as? String) ?? ((payload as? [String: Any])?["message"] as? String) ?? "\(payload ?? "unknown error")"
            return .error(message)
        case "next":
            guard let payload = obj["payload"] as? [String: Any], let d = payload["data"] as? [String: Any],
                  let m = d["liveMeasurement"] as? [String: Any], let ts = m["timestamp"] as? String, let date = DateParsing.parse(ts),
                  let power = (m["power"] as? NSNumber)?.doubleValue else { return .other("next without liveMeasurement") }
            func num(_ key: String) -> Double? { (m[key] as? NSNumber)?.doubleValue }
            return .measurement(LiveMeasurement(timestamp: date, power: power, accumulatedConsumption: num("accumulatedConsumption"),
                                                accumulatedCost: num("accumulatedCost"), currency: m["currency"] as? String,
                                                powerProduction: num("powerProduction"), minPower: num("minPower"),
                                                averagePower: num("averagePower"), maxPower: num("maxPower"),
                                                accumulatedProduction: num("accumulatedProduction"), accumulatedReward: num("accumulatedReward"),
                                                maxPowerProduction: num("maxPowerProduction")))
        default: return .other(type)
        }
    }

    static func json(_ obj: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), as: UTF8.self)
    }
}

/// Keeps a websocket subscription to Tibber's live measurements open, reconnecting with backoff.
/// Every failure is attributed to the socket it came from: a broken socket usually reports through both its
/// send and its receive callback, and a late error from an already replaced socket must not tear down the new one.
public final class LiveClient {
    public enum Status: Equatable { case idle, connecting, connected, reconnecting(in: Int), failed(String) }

    /// A Pulse reports every few seconds; a connection that stays silent this long is treated as dead.
    public static let silenceTimeout: TimeInterval = 60

    private let token: String
    private let homeId: String
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var stopped = false
    private var failures = 0
    private var pendingReconnect: DispatchWorkItem?
    private var watchdog: DispatchWorkItem?
    private let queue = DispatchQueue(label: "nl.newstory.tibber-menu-bar.live")

    public var onMeasurement: ((LiveMeasurement) -> Void)?
    public var onStatus: ((Status) -> Void)?

    public init(token: String, homeId: String, url: URL, session: URLSession = .shared) {
        self.token = token; self.homeId = homeId; self.url = url; self.session = session
    }

    public func start() {
        queue.async { [self] in
            stopped = false
            connect()
        }
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            pendingReconnect?.cancel(); pendingReconnect = nil
            watchdog?.cancel(); watchdog = nil
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
            onStatus?(.idle)
        }
    }

    private func connect() {
        guard !stopped else { return }
        pendingReconnect?.cancel(); pendingReconnect = nil
        // Never leave a previous socket open next to the new one.
        task?.cancel(with: .goingAway, reason: nil)
        onStatus?(.connecting)
        var request = URLRequest(url: url)
        request.setValue(LiveProtocol.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue(TibberClient.userAgent, forHTTPHeaderField: "User-Agent")
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        send(LiveProtocol.connectionInit(token: token), on: t)
        armWatchdog(for: t)   // a server that never acks is caught too
        receive(on: t)
    }

    private func send(_ text: String, on t: URLSessionWebSocketTask) {
        t.send(.string(text)) { [weak self] error in
            if let error { self?.handleFailure(error.localizedDescription, on: t) }
        }
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.task === t, !self.stopped else { return }
                switch result {
                case .failure(let error):
                    self.handleFailure(error.localizedDescription, on: t)
                case .success(let message):
                    let text: String
                    switch message {
                    case .string(let s): text = s
                    case .data(let d): text = String(decoding: d, as: UTF8.self)
                    @unknown default: text = ""
                    }
                    self.armWatchdog(for: t)
                    self.handle(LiveProtocol.parse(text), on: t)
                    self.receive(on: t)
                }
            }
        }
    }

    private func handle(_ incoming: LiveProtocol.Incoming, on t: URLSessionWebSocketTask) {
        switch incoming {
        case .ack:
            failures = 0
            onStatus?(.connected)
            send(LiveProtocol.subscribe(homeId: homeId), on: t)
        case .ping:
            send(LiveProtocol.pong, on: t)
        case .measurement(let m):
            onMeasurement?(m)
        case .error(let message):
            handleFailure(message, on: t)
        case .complete:
            handleFailure("subscription completed by server", on: t)
        case .other:
            break
        }
    }

    /// Restarts the silence timer; treats the connection as failed when nothing arrives within `silenceTimeout`.
    private func armWatchdog(for t: URLSessionWebSocketTask) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handleFailure("no data for \(Int(Self.silenceTimeout)) s", on: t) }
        watchdog = item
        queue.asyncAfter(deadline: .now() + Self.silenceTimeout, execute: item)
    }

    /// Only the first failure of the current socket counts; one reconnect per failure, after backoff.
    private func handleFailure(_ message: String, on t: URLSessionWebSocketTask) {
        queue.async { [self] in
            guard !stopped, task === t else { return }
            watchdog?.cancel(); watchdog = nil
            t.cancel(with: .goingAway, reason: nil)
            task = nil
            failures += 1
            let delay = min(60, 5 * failures)
            onStatus?(failures >= 5 ? .failed(message) : .reconnecting(in: delay))
            let item = DispatchWorkItem { [weak self] in self?.connect() }
            pendingReconnect = item
            queue.asyncAfter(deadline: .now() + .seconds(delay), execute: item)
        }
    }
}
