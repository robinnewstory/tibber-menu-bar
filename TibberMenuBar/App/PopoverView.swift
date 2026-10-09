import SwiftUI
import Charts
import TibberCore

/// The popover: two large tiles (price, power), three small ones (today, low/high, cheapest window),
/// then the chart card with a day switch. Hovering the chart shows a slot in its capsule; dragging also
/// moves the price tile, and releasing snaps back to the current slot.
struct PopoverView: View {
    @ObservedObject var model: PriceModel
    @State private var scrubbed: PricePoint?
    @State private var day: ChartDay = .today
    @Environment(\.openSettings) private var openSettings
    @Environment(\.isSnapshot) private var isSnapshot

    enum ChartDay: Hashable { case today, tomorrow, both }

    var body: some View {
        VStack(spacing: 12) {
            if !model.hasToken {
                onboarding
            } else if let data = model.data {
                topTiles(data)
                smallTiles(data)
                chartCard(data)
            } else if model.isLoading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading prices…") }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "bolt.slash").font(.title2)
                    if let error = model.lastError { Text(verbatim: error).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
                    else { Text("No prices yet").font(.callout) }
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            }
            footer
        }
        .padding(14)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .onChange(of: day) { _, _ in scrubbed = nil }
        .onAppear { day = (model.popover.chart.defaultDay == .both && model.data?.hasTomorrow == true) ? .both : .today }
    }

    // MARK: Top tiles

    private func topTiles(_ data: PriceData) -> some View {
        let shown = scrubbed ?? model.current
        let tier = shown.map(model.tier(for:))
        let accent = TierColor.color(tier)
        return HStack(spacing: 12) {
            Tile(accent: accent) {
                VStack(alignment: .leading, spacing: 4) {
                    caption(priceCaption(shown, data))
                    if let slot = shown {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(bigNumber(slot.total, data)).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            Text(bigUnit(data)).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(verbatim: tier?.localizedLabel ?? "")
                            if scrubbed == nil, let current = model.current, let next = data.next(after: current.startsAt) {
                                Text("· next \(PriceFormatter.menuBar(next.total, currency: data.currency, style: .cents)) \(model.trend?.arrow ?? "")")
                            }
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(accent).lineLimit(1)
                    } else {
                        Text("—").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        Text("no price for this moment").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 4) {
                    caption(String(localized: "Power now"))
                    if model.liveEnabled {
                        let live = model.freshLive ?? model.live
                        HStack(spacing: 10) {
                            PowerGauge(fraction: gaugeFraction(live), color: live == nil ? .gray : accent)
                            Text(live.map { LiveMeasurement.formatPower($0.power) } ?? "—")
                                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(model.freshLive == nil ? .secondary : .primary)
                        }
                        Text(powerSubline(live)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("—").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        if model.liveSupported { Text("turned off in Settings").font(.caption).foregroundStyle(.secondary) }
                        else { Text("needs a Tibber Pulse").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func gaugeFraction(_ live: LiveMeasurement?) -> Double {
        guard let live else { return 0 }
        let ceiling = max(live.maxPower ?? 0, 1000)
        return min(1, max(0, live.power / ceiling))
    }

    private func priceCaption(_ shown: PricePoint?, _ data: PriceData) -> String {
        guard let shown, scrubbed != nil else {
            return String(localized: "Price now · \(shown.map { PriceFormatter.time($0.startsAt, timeZone: data.timeZone) } ?? "–")")
        }
        let range = PriceFormatter.slotRange(shown, slotLength: data.resolution.slotLength, timeZone: data.timeZone)
        return isTomorrow(shown, data) ? String(localized: "Tomorrow · \(range)") : String(localized: "Selected · \(range)")
    }

    private func powerSubline(_ live: LiveMeasurement?) -> String {
        guard let live else { return liveStatusText }
        if model.freshLive == nil { return String(localized: "last reading \(Age.text(from: live.timestamp, to: model.now))") }
        if let peak = live.maxPower { return String(localized: "peak today \(LiveMeasurement.formatPower(peak))") }
        return String(localized: "live")
    }

    private var liveStatusText: String {
        switch model.liveStatus {
        case .idle: return String(localized: "stream off")
        case .connecting: return String(localized: "connecting to Pulse…")
        case .connected: return String(localized: "waiting for the first reading…")
        case .reconnecting(let s): return String(localized: "reconnecting in \(s) s")
        case .failed(let why): return String(localized: "stream failed: \(why)")
        }
    }

    // MARK: Small tiles

    private func smallTiles(_ data: PriceData) -> some View {
        let stats = PriceMath.stats(data.today)
        let live = model.live
        return HStack(spacing: 12) {
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    caption(String(localized: "Today"))
                    Text(verbatim: live?.accumulatedConsumption.map { $0.formatted(.number.precision(.fractionLength(1))) + " kWh" } ?? "—").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(verbatim: live?.accumulatedCost.map { PriceFormatter.currencyAmount($0, currency: live?.currency ?? data.currency) }
                         ?? (model.liveSupported ? String(localized: "no reading yet") : String(localized: "needs a Tibber Pulse"))).font(.caption).foregroundStyle(.secondary)
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    caption(String(localized: "Low · high"))
                    if let s = stats {
                        Text(verbatim: "\(cents(s.min.total)) · \(cents(s.max.total))").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(verbatim: "\(PriceFormatter.time(s.min.startsAt, timeZone: data.timeZone)) · \(PriceFormatter.time(s.max.startsAt, timeZone: data.timeZone))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("no prices").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if isSnapshot {
                            HStack(spacing: 3) {
                                Text("Cheapest \(model.notifications.plannerHours) h")
                                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                            }
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
                        } else {
                            Menu {
                                ForEach(Planner.durationsHours, id: \.self) { h in
                                    Button("\(h) h") { model.notifications.plannerHours = h }
                                }
                            } label: {
                                Text("Cheapest \(model.notifications.plannerHours) h")
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            model.notifications.cheapWindowStart.toggle()
                        } label: {
                            Image(systemName: model.notifications.cheapWindowStart ? "bell.fill" : "bell")
                                .font(.system(size: 10)).foregroundStyle(model.notifications.cheapWindowStart ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain).help("Notify me 10 minutes before this window starts")
                        .accessibilityLabel(model.notifications.cheapWindowStart ? "Window reminder on" : "Window reminder off")
                    }
                    if let w = model.plannedWindow {
                        Text(verbatim: windowStartText(w, data))
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Text("avg \(cents(w.average))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("no window in range").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func windowStartText(_ w: PlannedWindow, _ data: PriceData) -> String {
        let start = PriceFormatter.time(w.start, timeZone: data.timeZone)
        return data.today.contains { $0.startsAt == w.start } ? start : String(localized: "\(start) tmrw")
    }

    // MARK: Chart card

    private func chartCard(_ data: PriceData) -> some View {
        let points: [PricePoint]
        switch day {
        case .today: points = data.today
        case .tomorrow: points = data.tomorrow
        case .both: points = data.all
        }
        return Tile {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(day == .tomorrow ? "Tomorrow" : (day == .both ? "Today & tomorrow" : "Today")).font(.caption.weight(.semibold))
                    Spacer()
                    if isSnapshot {
                        daySwitchStandIn
                    } else {
                        Picker("Day", selection: $day) {
                            Text("Today").tag(ChartDay.today)
                            Text("Tomorrow").tag(ChartDay.tomorrow)
                            if data.hasTomorrow { Text("Both").tag(ChartDay.both) }
                        }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.mini).fixedSize()
                        .disabled(!data.hasTomorrow)
                    }
                }
                PriceChart(points: points, data: data, current: day == .tomorrow ? nil : model.current, now: model.now,
                           showMidnight: day == .both, options: model.popover.chart, window: model.plannedWindow, tierFor: model.tier(for:), selected: $scrubbed)
                    .frame(height: model.popover.chart.height.points)
                    .accessibilityLabel("Price chart")
            }
        }
    }

    /// Looks like the mini segmented control; only used in screenshots.
    private var daySwitchStandIn: some View {
        HStack(spacing: 2) {
            ForEach([("Today", true), ("Tomorrow", false), ("Both", false)], id: \.0) { title, selected in
                Text(LocalizedStringKey(title)).font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(selected ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: selected ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Pieces

    private func caption(_ text: String) -> some View {
        Text(verbatim: text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
    }

    private func cents(_ total: Double) -> String { PriceFormatter.menuBar(total, currency: model.data?.currency ?? "EUR", style: .cents) }

    private func bigNumber(_ total: Double, _ data: PriceData) -> String {
        switch model.menuBar.format {
        case .cents, .centsWhole:
            return PriceFormatter.menuBar(total, currency: data.currency, style: model.menuBar.format).replacingOccurrences(of: PriceFormatter.centSymbol(for: data.currency), with: "")
        case .currency, .currency3, .plain:
            return PriceFormatter.menuBar(total, currency: data.currency, style: model.menuBar.format)
        }
    }

    private func bigUnit(_ data: PriceData) -> String {
        switch model.menuBar.format {
        case .cents, .centsWhole: return "\(PriceFormatter.centSymbol(for: data.currency).trimmingCharacters(in: .whitespaces))/kWh"
        case .currency, .currency3, .plain: return "/kWh"
        }
    }

    private func isTomorrow(_ slot: PricePoint?, _ data: PriceData) -> Bool {
        guard let slot else { return false }
        return !data.today.contains(slot)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Tibber").font(.headline)
            Text("Create a personal access token on developer.tibber.com under Settings → Access Token, then paste it in this app's Settings. Prices appear in the menu bar right after.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Create a token…") { NSWorkspace.shared.open(URL(string: "https://developer.tibber.com/settings/access-token")!) }
                Button("Open Settings…") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let data = model.data {
                Text("Updated \(Age.text(from: data.fetchedAt, to: model.now))").font(.caption2).foregroundStyle(.secondary)
            }
            if model.isOffline {
                Label("offline", systemImage: "wifi.slash").font(.caption2).foregroundStyle(.orange).labelStyle(.titleAndIcon)
            } else if let error = model.lastError, model.data != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)
            }
            if model.consecutiveFailures > 0 {
                Text("retry in \(Int(Backoff.delay(afterFailures: model.consecutiveFailures) / 60)) min").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if isSnapshot {
                ForEach(["arrow.clockwise", "gearshape", "power"], id: \.self) { Image(systemName: $0).foregroundStyle(.secondary) }
            } else {
                Button { Task { await model.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.isLoading || !model.hasToken).help("Refresh now").accessibilityLabel("Refresh now")
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings").accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.borderless).help("Quit").accessibilityLabel("Quit")
            }
        }
    }
}
