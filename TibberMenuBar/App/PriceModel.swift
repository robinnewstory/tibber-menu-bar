import Foundation
import AppKit
import ServiceManagement
import TibberCore

/// Owns the token, the cached prices, the live stream and the refresh schedule. Everything the views show comes from here.
@MainActor
final class PriceModel: ObservableObject {
    static let shared = PriceModel()

    // Prices
    @Published private(set) var data: PriceData?
    @Published private(set) var homes: [HomeInfo] = []
    @Published private(set) var current: PricePoint?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var isOffline = false
    @Published private(set) var hasToken = false
    @Published var now = Date()

    // Live (Tibber Pulse)
    @Published private(set) var live: LiveMeasurement?
    @Published private(set) var liveStatus: LiveClient.Status = .idle
    private var liveClient: LiveClient?
    private var websocketURL: URL?
    private var liveWrittenAt: Date?

    // Settings
    private var suppressSideEffects = false
    @Published var selectedHomeId: String? = UserDefaults.standard.string(forKey: "homeId") {
        didSet {
            UserDefaults.standard.set(selectedHomeId, forKey: "homeId")
            if !suppressSideEffects, selectedHomeId != oldValue { Task { await refresh(force: true); restartLive() } }
        }
    }
    @Published var resolution: Resolution = Resolution(rawValue: UserDefaults.standard.string(forKey: "resolution") ?? "") ?? .quarterHourly {
        didSet {
            UserDefaults.standard.set(resolution.rawValue, forKey: "resolution")
            if !suppressSideEffects, resolution != oldValue { Task { await refresh(force: true) } }
        }
    }
    @Published var labelStyle: LabelStyle = LabelStyle(rawValue: UserDefaults.standard.string(forKey: "labelStyle") ?? "") ?? .cents {
        didSet { UserDefaults.standard.set(labelStyle.rawValue, forKey: "labelStyle") }
    }
    @Published var showIcon: Bool = UserDefaults.standard.object(forKey: "showIcon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showIcon, forKey: "showIcon") }
    }
    @Published var showTrend: Bool = UserDefaults.standard.object(forKey: "showTrend") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showTrend, forKey: "showTrend") }
    }
    @Published var showLivePower: Bool = UserDefaults.standard.object(forKey: "showLivePower") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showLivePower, forKey: "showLivePower"); restartLive() }
    }
    @Published var notificationPrefs: NotificationPrefs = PriceModel.loadPrefs() {
        didSet {
            if let d = try? JSONEncoder().encode(notificationPrefs) { UserDefaults.standard.set(d, forKey: "notificationPrefs") }
            if notificationPrefs.anyEnabled { Task { await NotificationManager.shared.requestAuthorization() } }
        }
    }
    private var notificationState: NotificationState = PriceModel.loadState() {
        didSet { if let d = try? JSONEncoder().encode(notificationState) { UserDefaults.standard.set(d, forKey: "notificationState") } }
    }

    private let cache = PriceCache()
    private let tokenStore = TokenStore.keychain
    private var timer: Timer?
    private var started = false

    private static func loadPrefs() -> NotificationPrefs {
        guard let d = UserDefaults.standard.data(forKey: "notificationPrefs"), let p = try? JSONDecoder().decode(NotificationPrefs.self, from: d) else { return NotificationPrefs() }
        return p
    }
    private static func loadState() -> NotificationState {
        guard let d = UserDefaults.standard.data(forKey: "notificationState"), let s = try? JSONDecoder().decode(NotificationState.self, from: d) else { return NotificationState() }
        return s
    }

    // MARK: Derived

    var selectedHome: HomeInfo? { homes.first { $0.id == selectedHomeId } ?? data?.home }
    var liveSupported: Bool { selectedHome?.liveMeasurements ?? false }
    /// A reading is "fresh" for a minute; after that the menu bar stops showing it.
    var freshLive: LiveMeasurement? {
        guard let live, now.timeIntervalSince(live.timestamp) < 60 else { return nil }
        return live
    }
    var trend: Trend? {
        guard let data, let current else { return nil }
        return Trend.between(current: current, next: data.next(after: current.startsAt))
    }
    var plannedWindow: PlannedWindow? {
        guard let data else { return nil }
        return Planner.cheapestWindow(in: data, hours: notificationPrefs.plannerHours, from: now)
    }

    // MARK: Menu bar label

    var menuTitle: String {
        guard hasToken else { return "Tibber" }
        guard let current, let data else { return isLoading ? "…" : "–" }
        var parts = [PriceFormatter.menuBar(current.total, currency: data.currency, style: labelStyle)]
        if showTrend, let trend { parts[0] += " " + trend.arrow }
        if showLivePower, let live = freshLive { parts.append(LiveMeasurement.formatPower(live.power)) }
        return parts.joined(separator: " · ")
    }

    var menuSymbol: String {
        guard showIcon else { return "" }
        if !hasToken || (lastError != nil && data == nil) { return "bolt.slash" }
        if isOffline { return "wifi.slash" }
        switch current?.level {
        case .veryCheap?, .cheap?: return "bolt.fill"
        case .expensive?, .veryExpensive?: return "bolt.trianglebadge.exclamationmark.fill"
        default: return "bolt"
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        hasToken = ((try? tokenStore.load()) ?? nil)?.isEmpty == false
        data = cache.load()
        updateCurrent()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.restartLive()
            }
        }
        if notificationPrefs.anyEnabled { Task { await NotificationManager.shared.requestAuthorization() } }
        Task {
            await loadHomes()
            await refresh(force: false)
            restartLive()
        }
    }

    private func tick() {
        now = Date()
        updateCurrent()
        let reason = RefreshPolicy.reason(data: data, lastAttempt: lastAttempt, now: now)
        if reason != .none, Backoff.mayRetry(failures: consecutiveFailures, lastAttempt: lastAttempt, now: now) {
            Task { await refresh(force: false) }
        }
        evaluateNotifications()
    }

    private func updateCurrent() {
        current = data?.current(at: Date())
    }

    private func evaluateNotifications() {
        guard let data, notificationPrefs.anyEnabled else { return }
        var state = notificationState
        let events = NotificationRules.events(data: data, prefs: notificationPrefs, state: &state, now: now)
        if state != notificationState { notificationState = state }
        for event in events {
            let text = NotificationRules.text(for: event, timeZone: data.timeZone, style: labelStyle)
            NotificationManager.shared.deliver(title: text.title, body: text.body)
        }
    }

    // MARK: Token & homes

    /// Removes what people paste by accident: a "Bearer " prefix, quotes, line breaks and inner whitespace.
    static func sanitize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("bearer ") { t = String(t.dropFirst(7)) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        return t.filter { !$0.isWhitespace && !$0.isNewline }
    }

    func saveToken(_ raw: String) async -> Bool {
        let token = Self.sanitize(raw)
        if token.lowercased().hasPrefix("http") || token.contains("/") || token.contains(":") {
            lastError = "That is a web address, not a token. On developer.tibber.com → Settings → Access Token, create a token and use its copy button, then paste it here."
            return false
        }
        if !token.isEmpty, token.count < 20 || !token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) {
            lastError = "That doesn't look like a Tibber access token. Copy the whole token from developer.tibber.com → Settings → Access Token."
            return false
        }
        do {
            try tokenStore.save(token)
        } catch {
            lastError = "Could not store the token in the Keychain: \(error.localizedDescription)"
            return false
        }
        hasToken = !token.isEmpty
        lastError = nil
        consecutiveFailures = 0
        guard hasToken else { data = nil; current = nil; stopLive(); return true }
        await loadHomes()
        await refresh(force: true)
        restartLive()
        return lastError == nil
    }

    func clearToken() {
        try? tokenStore.save(nil)
        hasToken = false
        homes = []
        data = nil
        current = nil
        lastError = nil
        stopLive()
    }

    func loadHomes() async {
        guard let token = try? tokenStore.load(), !token.isEmpty else { return }
        do {
            let account = try await TibberClient(token: token).fetchAccount()
            homes = account.homes
            websocketURL = account.websocketURL
            if selectedHomeId == nil || !homes.contains(where: { $0.id == selectedHomeId }) {
                suppressSideEffects = true
                selectedHomeId = homes.first(where: \.hasSubscription)?.id ?? homes.first?.id
                suppressSideEffects = false
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Refresh

    func refresh(force: Bool) async {
        guard !isLoading else { return }
        guard let token = try? tokenStore.load(), !token.isEmpty else { hasToken = false; return }
        hasToken = true
        if !force && RefreshPolicy.reason(data: data, lastAttempt: lastAttempt, now: Date()) == .none { return }
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }
        do {
            let fresh = try await TibberClient(token: token).fetchPrices(homeId: selectedHomeId, resolution: resolution)
            data = fresh
            cache.save(fresh)
            lastError = nil
            consecutiveFailures = 0
            isOffline = false
            if homes.isEmpty { await loadHomes() }
        } catch {
            consecutiveFailures += 1
            isOffline = Self.isOfflineError(error)
            lastError = isOffline ? "Offline — showing cached prices" : error.localizedDescription
        }
        updateCurrent()
        evaluateNotifications()
    }

    static func isOfflineError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    // MARK: Live measurements (Tibber Pulse)

    func restartLive() {
        stopLive()
        guard showLivePower, hasToken, liveSupported, let url = websocketURL, let homeId = selectedHomeId,
              let token = try? tokenStore.load(), !token.isEmpty else { return }
        let client = LiveClient(token: token, homeId: homeId, url: url)
        client.onMeasurement = { [weak self] m in
            Task { @MainActor in
                guard let self else { return }
                self.live = m
                self.now = Date()
                if self.liveWrittenAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
                    self.liveWrittenAt = Date()
                    LiveSnapshot.write(m)
                }
            }
        }
        client.onStatus = { [weak self] status in Task { @MainActor in self?.liveStatus = status } }
        liveClient = client
        client.start()
    }

    func stopLive() {
        liveClient?.stop()
        liveClient = nil
        live = nil
        liveStatus = .idle
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}

/// Latest live reading on disk, so `--status` can show whether the Pulse stream works.
enum LiveSnapshot {
    static var url: URL { PriceCache().url.deletingLastPathComponent().appendingPathComponent("live.json") }
    static func write(_ m: LiveMeasurement) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let d = try? e.encode(m) { try? d.write(to: url, options: .atomic) }
    }
    static func read() -> LiveMeasurement? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(LiveMeasurement.self, from: d)
    }
}
