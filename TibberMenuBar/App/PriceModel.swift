import Foundation
import AppKit
import ServiceManagement
import TibberCore

/// Owns the token, the cached prices and the refresh schedule. Everything the views show comes from here.
@MainActor
final class PriceModel: ObservableObject {
    static let shared = PriceModel()

    @Published private(set) var data: PriceData?
    @Published private(set) var homes: [HomeInfo] = []
    @Published private(set) var current: PricePoint?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var hasToken = false
    @Published var now = Date()

    /// Set while initialising so changing a setting programmatically doesn't trigger a refresh.
    private var suppressSideEffects = false

    @Published var selectedHomeId: String? = UserDefaults.standard.string(forKey: "homeId") {
        didSet {
            UserDefaults.standard.set(selectedHomeId, forKey: "homeId")
            if !suppressSideEffects, selectedHomeId != oldValue { Task { await refresh(force: true) } }
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

    private let cache = PriceCache()
    private let tokenStore = TokenStore.keychain
    private var timer: Timer?
    private var started = false

    // MARK: Menu bar label

    var menuTitle: String {
        guard hasToken else { return "Tibber" }
        guard let current, let data else { return isLoading ? "…" : "–" }
        return PriceFormatter.menuBar(current.total, currency: data.currency, style: labelStyle)
    }

    var menuSymbol: String {
        guard showIcon else { return "" }
        if !hasToken || lastError != nil && data == nil { return "bolt.slash" }
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
            Task { @MainActor in self?.tick() }
        }
        Task { await refresh(force: false) }
    }

    private func tick() {
        now = Date()
        updateCurrent()
        if RefreshPolicy.reason(data: data, lastAttempt: lastAttempt, now: now) != .none {
            Task { await refresh(force: false) }
        }
    }

    private func updateCurrent() {
        current = data?.current(at: Date())
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
        hasToken = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastError = nil
        guard hasToken else { data = nil; current = nil; return true }
        await loadHomes()
        await refresh(force: true)
        return lastError == nil
    }

    func clearToken() {
        try? tokenStore.save(nil)
        hasToken = false
        homes = []
        data = nil
        current = nil
        lastError = nil
    }

    func loadHomes() async {
        guard let token = try? tokenStore.load(), !token.isEmpty else { return }
        do {
            homes = try await TibberClient(token: token).fetchHomes()
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
            if homes.isEmpty { await loadHomes() }
        } catch {
            lastError = error.localizedDescription
        }
        updateCurrent()
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
