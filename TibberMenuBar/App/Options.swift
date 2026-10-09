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
    enum Palette: String, Codable, CaseIterable {
        case standard, colorblind
        var label: String { switch self { case .standard: return String(localized: "Standard"); case .colorblind: return String(localized: "Colorblind-friendly") } }
    }
    var homeId: String?
    var resolution: Resolution = .quarterHourly
    var levelSource: LevelSource = .tibber
    var palette: Palette = .standard

    init() {}
    // Options added after a release decode as their defaults, so an older settings file never resets everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeId = try c.decodeIfPresent(String.self, forKey: .homeId)
        resolution = try c.decodeIfPresent(Resolution.self, forKey: .resolution) ?? .quarterHourly
        levelSource = try c.decodeIfPresent(LevelSource.self, forKey: .levelSource) ?? .tibber
        palette = try c.decodeIfPresent(Palette.self, forKey: .palette) ?? .standard
    }
}

/// What the menu bar label shows.
struct MenuBarOptions: Codable, Equatable {
    static let key = "options.menuBar"
    enum Icon: String, Codable, CaseIterable {
        case bolt, dot, none
        var label: String {
            switch self { case .bolt: return String(localized: "Bolt"); case .dot: return String(localized: "Level dot"); case .none: return String(localized: "None") }
        }
    }
    var format: LabelStyle = .cents
    var icon: Icon = .bolt
    var trendArrow = true
    var nextPrice = false
    var levelWord = false
    var livePower = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(LabelStyle.self, forKey: .format) ?? .cents
        icon = try c.decodeIfPresent(Icon.self, forKey: .icon) ?? .bolt
        trendArrow = try c.decodeIfPresent(Bool.self, forKey: .trendArrow) ?? true
        nextPrice = try c.decodeIfPresent(Bool.self, forKey: .nextPrice) ?? false
        levelWord = try c.decodeIfPresent(Bool.self, forKey: .levelWord) ?? false
        livePower = try c.decodeIfPresent(Bool.self, forKey: .livePower) ?? false
    }
}

/// What the popover shows and how the chart is drawn.
struct PopoverOptions: Codable, Equatable {
    static let key = "options.popover"
    var livePower = true
    var chart = ChartOptions()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        livePower = try c.decodeIfPresent(Bool.self, forKey: .livePower) ?? true
        chart = try c.decodeIfPresent(ChartOptions.self, forKey: .chart) ?? ChartOptions()
    }
}

struct ChartOptions: Codable, Equatable {
    enum Style: String, Codable, CaseIterable {
        case bars, line, area
        var label: String { switch self { case .bars: return String(localized: "Bars"); case .line: return String(localized: "Step line"); case .area: return String(localized: "Area") } }
    }
    enum ColorMode: String, Codable, CaseIterable {
        case tier, mono
        var label: String { switch self { case .tier: return String(localized: "By price level"); case .mono: return String(localized: "Single color") } }
    }
    enum Height: String, Codable, CaseIterable {
        case compact, normal, tall
        var label: String { switch self { case .compact: return String(localized: "Compact"); case .normal: return String(localized: "Normal"); case .tall: return String(localized: "Tall") } }
        var points: CGFloat { switch self { case .compact: return 130; case .normal: return 170; case .tall: return 220 } }
    }
    enum DefaultDay: String, Codable, CaseIterable {
        case today, both
        var label: String { switch self { case .today: return String(localized: "Today"); case .both: return String(localized: "Today and tomorrow") } }
    }
    var style: Style = .bars
    var colorMode: ColorMode = .tier
    var showAverage = true
    var shadeWindow = true
    var dimPast = true
    var fromZero = false
    var height: Height = .normal
    var defaultDay: DefaultDay = .today

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = try c.decodeIfPresent(Style.self, forKey: .style) ?? .bars
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? .tier
        showAverage = try c.decodeIfPresent(Bool.self, forKey: .showAverage) ?? true
        shadeWindow = try c.decodeIfPresent(Bool.self, forKey: .shadeWindow) ?? true
        dimPast = try c.decodeIfPresent(Bool.self, forKey: .dimPast) ?? true
        fromZero = try c.decodeIfPresent(Bool.self, forKey: .fromZero) ?? false
        height = try c.decodeIfPresent(Height.self, forKey: .height) ?? .normal
        defaultDay = try c.decodeIfPresent(DefaultDay.self, forKey: .defaultDay) ?? .today
    }
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
