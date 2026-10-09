import Foundation
import AppKit
import ServiceManagement
import TibberCore

/// Owns the token, the cached prices, the live stream and the refresh schedule. Everything the views show comes from here.
@MainActor
final class PriceModel: ObservableObject {
    static let shared = PriceModel()

    // MARK: State

    @Published private(set) var data: PriceData? {
        didSet {
            todayAverage = PriceMath.stats(data?.today ?? [])?.average
            tomorrowAverage = PriceMath.stats(data?.tomorrow ?? [])?.average
        }
    }
    @Published private(set) var homes: [HomeInfo] = []
    @Published private(set) var current: PricePoint?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var isOffline = false
    @Published private(set) var hasToken = false
    @Published var now = Date()

    @Published private(set) var live: LiveMeasurement?
    @Published private(set) var liveStatus: LiveClient.Status = .idle

    // MARK: Settings

    @Published var prices: PriceOptions = Persisted.load(PriceOptions.key, default: PriceOptions()) {
        didSet {
            Persisted.save(prices, key: PriceOptions.key)
            guard !suppressSideEffects else { return }
            if prices.homeId != oldValue.homeId || prices.resolution != oldValue.resolution {
                Task { await refresh(force: true) }
            }
            if prices.homeId != oldValue.homeId { restartLive() }
        }
    }
    @Published var menuBar: MenuBarOptions = Persisted.load(MenuBarOptions.key, default: MenuBarOptions()) {
        didSet { Persisted.save(menuBar, key: MenuBarOptions.key) }
    }
    @Published var popover: PopoverOptions = Persisted.load(PopoverOptions.key, default: PopoverOptions()) {
        didSet {
            Persisted.save(popover, key: PopoverOptions.key)
            if popover.livePower != oldValue.livePower { restartLive() }
        }
    }
    @Published var notifications: NotificationPrefs = Persisted.load("notificationPrefs", default: NotificationPrefs()) {
        didSet {
            Persisted.save(notifications, key: "notificationPrefs")
            if notifications.anyEnabled, !oldValue.anyEnabled || notifications != oldValue {
                Task { await NotificationManager.shared.requestAuthorization() }
            }
        }
    }
    private var notificationState: NotificationState = Persisted.load("notificationState", default: NotificationState()) {
        didSet { Persisted.save(notificationState, key: "notificationState") }
    }

    private var suppressSideEffects = false
    private var todayAverage: Double?
    private var tomorrowAverage: Double?
    private var liveClient: LiveClient?
    private var websocketURL: URL?
    private var liveSnapshotWrittenAt: Date?
    private var liveCountSince = Date()
    private var liveCount = 0
    private let cache = PriceCache()
    private let tokenStore = TokenStore.keychain
    private var timer: Timer?
    private var started = false
    private var homesAttemptAt: Date?
    private var refreshQueued = false

    // MARK: Derived values

    var selectedHome: HomeInfo? { homes.first { $0.id == prices.homeId } ?? data?.home }
    var liveSupported: Bool { selectedHome?.liveMeasurements ?? false }
    var liveEnabled: Bool { liveSupported && popover.livePower }

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
        return Planner.cheapestWindow(in: data, hours: notifications.plannerHours, from: now)
    }

    /// How expensive a slot is, by the configured definition (Tibber's level or the day's average).
    func tier(for point: PricePoint) -> DisplayTier {
        let average = data?.today.contains(point) == true ? todayAverage : tomorrowAverage
        return TierResolver.tier(for: point, source: prices.levelSource, dayAverage: average)
    }
    var currentTier: DisplayTier? { current.map(tier(for:)) }

    // MARK: Menu bar label

    var menuTitle: String {
        guard hasToken else { return "Tibber" }
        guard let current, let data else { return isLoading ? "…" : "–" }
        var first = PriceFormatter.menuBar(current.total, currency: data.currency, style: menuBar.format)
        if menuBar.trendArrow, let trend { first += " " + trend.arrow }
        if menuBar.nextPrice, let next = data.next(after: current.startsAt) {
            first += (menuBar.trendArrow ? " " : " → ") + PriceFormatter.menuBar(next.total, currency: data.currency, style: menuBar.format)
        }
        var parts = [first]
        if menuBar.levelWord, let tier = currentTier { parts.append(tier.localizedLabel) }
        if menuBar.livePower, liveEnabled, let live = freshLive { parts.append(LiveMeasurement.formatPower(live.netPower)) }
        return parts.joined(separator: " · ")
    }

    var menuSymbol: String {
        if !hasToken || (lastError != nil && data == nil) { return "bolt.slash" }
        if isOffline { return "wifi.slash" }
        switch currentTier {
        case .veryCheap?, .cheap?: return "bolt.fill"
        case .expensive?, .veryExpensive?: return "bolt.trianglebadge.exclamationmark.fill"
        default: return "bolt"
        }
    }

    /// A small filled circle in the tier's color, for the "level dot" icon.
    var menuDot: NSImage {
        let color = TierColor.nsColor(currentTier, palette: prices.palette)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        LegacySettings.migrateIfNeeded()
        prices = Persisted.load(PriceOptions.key, default: PriceOptions())
        menuBar = Persisted.load(MenuBarOptions.key, default: MenuBarOptions())
        popover = Persisted.load(PopoverOptions.key, default: PopoverOptions())
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
        if notifications.anyEnabled { Task { await NotificationManager.shared.requestAuthorization() } }
        Task {
            await loadHomes()   // also starts the live stream once the websocket URL is known
            await refresh(force: false)
        }
    }

    private func tick() {
        now = Date()
        updateCurrent()
        // Launching at login often happens before the network is up; keep asking for the homes (and the
        // websocket URL) until they are known, at most every five minutes.
        if hasToken, homes.isEmpty, homesAttemptAt.map({ now.timeIntervalSince($0) >= 5 * 60 }) ?? true {
            Task { await loadHomes() }
        }
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
        guard let data, notifications.anyEnabled else { return }
        var state = notificationState
        let events = NotificationRules.events(data: data, prefs: notifications, state: &state, now: now)
        if state != notificationState { notificationState = state }
        for event in events {
            let text = NotificationText.text(for: event, timeZone: data.timeZone, style: menuBar.format)
            NotificationManager.shared.deliver(title: text.title, body: text.body)
        }
    }

    /// Demo prices and a demo Pulse reading, for `--snapshot`. Never starts timers or network.
    func loadDemo() {
        hasToken = true
        data = DemoData.prices(now: now)
        live = DemoData.live(now: now)
        liveStatus = .connected
        updateCurrent()
    }

    // MARK: Token and homes

    /// Removes what people paste by accident: a "Bearer " prefix, quotes, line breaks and inner whitespace.
    static func sanitize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("bearer ") { t = String(t.dropFirst(7)) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        return t.filter { !$0.isWhitespace && !$0.isNewline }
    }

    /// Stores a token and connects. Returns a user-facing problem description, or nil on success.
    func saveToken(_ raw: String) async -> String? {
        let token = Self.sanitize(raw)
        if token.lowercased().hasPrefix("http") || token.contains("/") || token.contains(":") {
            return String(localized: "That is a web address, not a token. On developer.tibber.com → Settings → Access Token, create a token and use its copy button.")
        }
        if token.count < 20 || !token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) {
            return String(localized: "That doesn't look like a Tibber access token. Copy the whole token from developer.tibber.com → Settings → Access Token.")
        }
        do {
            try tokenStore.save(token)
        } catch {
            return String(localized: "Could not store the token in the Keychain: \(error.localizedDescription)")
        }
        hasToken = true
        lastError = nil
        consecutiveFailures = 0
        stopLive()   // a replaced token must not keep the old stream; loadHomes starts a fresh one
        await loadHomes()
        await refresh(force: true)
        return lastError
    }

    func clearToken() {
        try? tokenStore.save(nil)
        hasToken = false
        homes = []
        websocketURL = nil
        data = nil
        current = nil
        lastError = nil
        refreshQueued = false
        stopLive()
        // Disconnecting leaves nothing of the account behind: home name and city, prices, consumption and cost.
        cache.clear()
        LiveSnapshot.clear()
        notificationState = NotificationState()
    }

    func loadHomes() async {
        guard let token = try? tokenStore.load(), !token.isEmpty else { return }
        homesAttemptAt = Date()
        do {
            let account = try await TibberClient(token: token).fetchAccount()
            guard (try? tokenStore.load()) == token else { return }   // disconnected or replaced meanwhile
            homes = account.homes
            websocketURL = account.websocketURL
            if prices.homeId == nil || !homes.contains(where: { $0.id == prices.homeId }) {
                suppressSideEffects = true
                prices.homeId = homes.first(where: \.hasSubscription)?.id ?? homes.first?.id
                suppressSideEffects = false
            }
            if liveEnabled, liveClient == nil { restartLive() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Refresh

    func refresh(force: Bool) async {
        guard !isLoading else {
            // A forced refresh (other home, other resolution, new token) must not be lost behind the one in flight.
            if force { refreshQueued = true }
            return
        }
        guard let token = try? tokenStore.load(), !token.isEmpty else { hasToken = false; return }
        hasToken = true
        if !force && RefreshPolicy.reason(data: data, lastAttempt: lastAttempt, now: Date()) == .none { return }
        isLoading = true
        lastAttempt = Date()
        do {
            let fresh = try await TibberClient(token: token).fetchPrices(homeId: prices.homeId, resolution: prices.resolution)
            guard (try? tokenStore.load()) == token else { isLoading = false; return }   // disconnected or replaced meanwhile
            data = fresh
            cache.save(fresh)
            lastError = nil
            consecutiveFailures = 0
            isOffline = false
            if homes.isEmpty { await loadHomes() }
        } catch {
            consecutiveFailures += 1
            isOffline = Self.isOfflineError(error)
            lastError = isOffline ? String(localized: "Offline, showing cached prices") : ErrorText.describe(error)
        }
        isLoading = false
        updateCurrent()
        evaluateNotifications()
        if refreshQueued {
            refreshQueued = false
            await refresh(force: true)
        }
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
        guard liveEnabled, hasToken, let url = websocketURL, let homeId = prices.homeId,
              let token = try? tokenStore.load(), !token.isEmpty else { return }
        let client = LiveClient(token: token, homeId: homeId, url: url)
        client.onMeasurement = { [weak self] measurement in
            Task { @MainActor in self?.receive(measurement) }
        }
        client.onStatus = { [weak self] status in Task { @MainActor in self?.liveStatus = status } }
        liveClient = client
        client.start()
    }

    private func receive(_ measurement: LiveMeasurement) {
        live = measurement
        now = Date()
        liveCount += 1
        if liveSnapshotWrittenAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
            liveSnapshotWrittenAt = Date()
            LiveSnapshot.write(measurement, messages: liveCount, since: liveCountSince)
            liveCount = 0
            liveCountSince = Date()
        }
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
                lastError = String(localized: "Launch at login: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}

/// Latest live reading on disk (plus the message rate since the previous write), so `--status` can show whether the Pulse stream works.
struct LiveSnapshotRecord: Codable {
    let measurement: LiveMeasurement
    let messages: Int
    let since: Date
    let writtenAt: Date
}

enum LiveSnapshot {
    static var url: URL { PriceCache().url.deletingLastPathComponent().appendingPathComponent("live.json") }
    static func write(_ m: LiveMeasurement, messages: Int, since: Date) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let d = try? e.encode(LiveSnapshotRecord(measurement: m, messages: messages, since: since, writtenAt: Date())) { try? d.write(to: url, options: .atomic) }
    }
    static func clear() { try? FileManager.default.removeItem(at: url) }
    static func read() -> LiveSnapshotRecord? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(LiveSnapshotRecord.self, from: d)
    }
}
