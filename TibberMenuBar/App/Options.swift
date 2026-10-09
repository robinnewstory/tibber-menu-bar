import Foundation
import TibberCore

/// One Codable value per settings group, stored as JSON in UserDefaults.
enum Persisted {
    static func load<T: Codable>(_ key: String, default value: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode(T.self, from: data) else { return value }
        return decoded
    }
    static func save<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Which prices to fetch and what "cheap" means.
struct PriceOptions: Codable, Equatable {
    static let key = "options.prices"
    var homeId: String?
    var resolution: Resolution = .quarterHourly
    var levelSource: LevelSource = .tibber
}

/// What the menu bar label shows.
struct MenuBarOptions: Codable, Equatable {
    static let key = "options.menuBar"
    enum Icon: String, Codable, CaseIterable {
        case bolt, dot, none
        var label: String {
            switch self { case .bolt: return "Bolt"; case .dot: return "Level dot"; case .none: return "None" }
        }
    }
    var format: LabelStyle = .cents
    var icon: Icon = .bolt
    var trendArrow = true
    var nextPrice = false
    var levelWord = false
    var livePower = false
}

/// What the popover shows and how the chart is drawn.
struct PopoverOptions: Codable, Equatable {
    static let key = "options.popover"
    var livePower = true
    var chart = ChartOptions()
}

struct ChartOptions: Codable, Equatable {
    enum Style: String, Codable, CaseIterable {
        case bars, line, area
        var label: String { switch self { case .bars: return "Bars"; case .line: return "Step line"; case .area: return "Area" } }
    }
    enum ColorMode: String, Codable, CaseIterable {
        case tier, mono
        var label: String { switch self { case .tier: return "By price level"; case .mono: return "Single color" } }
    }
    enum Height: String, Codable, CaseIterable {
        case compact, normal, tall
        var label: String { switch self { case .compact: return "Compact"; case .normal: return "Normal"; case .tall: return "Tall" } }
        var points: CGFloat { switch self { case .compact: return 130; case .normal: return 170; case .tall: return 220 } }
    }
    enum DefaultDay: String, Codable, CaseIterable {
        case today, both
        var label: String { switch self { case .today: return "Today"; case .both: return "Today and tomorrow" } }
    }
    var style: Style = .bars
    var colorMode: ColorMode = .tier
    var showAverage = true
    var shadeWindow = true
    var dimPast = true
    var fromZero = false
    var height: Height = .normal
    var defaultDay: DefaultDay = .today
}

/// Carries settings from the first versions (one UserDefaults key per option) into the grouped structs. Runs once.
enum LegacySettings {
    static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard d.data(forKey: PriceOptions.key) == nil, d.object(forKey: "labelStyle") != nil || d.object(forKey: "homeId") != nil else { return }
        var prices = PriceOptions()
        prices.homeId = d.string(forKey: "homeId")
        prices.resolution = Resolution(rawValue: d.string(forKey: "resolution") ?? "") ?? .quarterHourly
        prices.levelSource = LevelSource(rawValue: d.string(forKey: "levelSource") ?? "") ?? .tibber
        Persisted.save(prices, key: PriceOptions.key)

        var menu = MenuBarOptions()
        menu.format = LabelStyle(rawValue: d.string(forKey: "labelStyle") ?? "") ?? .cents
        if let raw = d.string(forKey: "iconStyle"), let icon = MenuBarOptions.Icon(rawValue: raw) { menu.icon = icon }
        else if d.object(forKey: "showIcon") as? Bool == false { menu.icon = .none }
        menu.trendArrow = d.object(forKey: "showTrend") as? Bool ?? true
        menu.nextPrice = d.bool(forKey: "showNext")
        menu.levelWord = d.bool(forKey: "showLevelWord")
        menu.livePower = d.bool(forKey: "liveInMenuBar")
        Persisted.save(menu, key: MenuBarOptions.key)

        var popover = PopoverOptions()
        popover.livePower = d.object(forKey: "showLivePower") as? Bool ?? true
        popover.chart = Persisted.load("chartOptions", default: ChartOptions())
        Persisted.save(popover, key: PopoverOptions.key)

        for key in ["homeId", "resolution", "levelSource", "labelStyle", "iconStyle", "showIcon", "showTrend", "showNext", "showLevelWord", "liveInMenuBar", "showLivePower", "chartOptions"] {
            d.removeObject(forKey: key)
        }
    }
}
