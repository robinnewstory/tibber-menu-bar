import SwiftUI
import Charts
import TibberCore

/// Option C: a tile dashboard. Two large tiles (price, power), three small ones (today, low/high, cheapest window),
/// then the chart card with a day switch. Hover shows a slot in the capsule; drag also moves the price tile.
struct PopoverView: View {
    @ObservedObject var model: PriceModel
    @State private var scrubbed: PricePoint?
    @State private var day: ChartDay = .today
    @Environment(\.openSettings) private var openSettings

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
                    Text(model.lastError ?? "No prices yet").font(.callout).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            }
            footer
        }
        .padding(14)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .onChange(of: day) { _, _ in scrubbed = nil }
    }

    // MARK: Top tiles

    private func topTiles(_ data: PriceData) -> some View {
        let shown = scrubbed ?? model.current
        let tier = shown.map { PriceMath.relativeTier($0.total, average: PriceMath.stats(data.today)?.average ?? $0.total) }
        let accent = TierColor.color(tier)
        return HStack(spacing: 12) {
            Tile(accent: accent) {
                VStack(alignment: .leading, spacing: 4) {
                    caption(scrubbed == nil ? "Price now · \(shown.map { PriceFormatter.time($0.startsAt, timeZone: data.timeZone) } ?? "–")"
                            : "\(isTomorrow(shown, data) ? "Tomorrow" : "Selected") · \(PriceFormatter.slotRange(shown!, slotLength: data.resolution.slotLength, timeZone: data.timeZone))")
                    if let slot = shown {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(bigNumber(slot.total, data)).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            Text(bigUnit(data)).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(tier.map(TierColor.label) ?? "")
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
                    caption("Power now")
                    if model.liveSupported && model.showLivePower {
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
                        Text(model.liveSupported ? "live power is off in Settings" : "needs a Tibber Pulse").font(.caption).foregroundStyle(.secondary)
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

    private func powerSubline(_ live: LiveMeasurement?) -> String {
        guard let live else { return liveStatusText }
        if model.freshLive == nil { return "last reading \(Age.text(from: live.timestamp, to: model.now))" }
        if let peak = live.maxPower { return "peak today \(LiveMeasurement.formatPower(peak))" }
        return "live"
    }

    private var liveStatusText: String {
        switch model.liveStatus {
        case .idle: return "live power off"
        case .connecting: return "connecting to Pulse…"
        case .connected: return "waiting for a reading…"
        case .reconnecting(let s): return "reconnecting in \(s) s"
        case .failed(let why): return "failed: \(why)"
        }
    }

    // MARK: Small tiles

    private func smallTiles(_ data: PriceData) -> some View {
        let stats = PriceMath.stats(data.today)
        let live = model.live
        return HStack(spacing: 12) {
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    caption("Today")
                    Text(live?.accumulatedConsumption.map { String(format: "%.1f kWh", $0) } ?? "—").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(live?.accumulatedCost.map { PriceFormatter.currencyAmount($0, currency: live?.currency ?? data.currency) } ?? "needs Pulse").font(.caption).foregroundStyle(.secondary)
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    caption("Low · high")
                    if let s = stats {
                        Text("\(cents(s.min.total)) · \(cents(s.max.total))").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(PriceFormatter.time(s.min.startsAt, timeZone: data.timeZone)) · \(PriceFormatter.time(s.max.startsAt, timeZone: data.timeZone))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("no prices").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Menu {
                            ForEach(Planner.durationsHours, id: \.self) { h in
                                Button("\(h) h") { model.notificationPrefs.plannerHours = h }
                            }
                        } label: {
                            Text("Cheapest \(model.notificationPrefs.plannerHours) h")
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button {
                            model.notificationPrefs.cheapWindowStart.toggle()
                        } label: {
                            Image(systemName: model.notificationPrefs.cheapWindowStart ? "bell.fill" : "bell")
                                .font(.system(size: 10)).foregroundStyle(model.notificationPrefs.cheapWindowStart ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain).help("Notify me 10 minutes before this window starts")
                    }
                    if let w = model.plannedWindow {
                        Text(PriceFormatter.time(w.start, timeZone: data.timeZone) + (data.today.contains { $0.startsAt == w.start } ? "" : " tmrw"))
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
                    Picker("", selection: $day) {
                        Text("Today").tag(ChartDay.today)
                        Text("Tomorrow").tag(ChartDay.tomorrow)
                        if data.hasTomorrow { Text("Both").tag(ChartDay.both) }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.mini).fixedSize()
                    .disabled(!data.hasTomorrow)
                }
                PriceChart(points: points, data: data, current: day == .tomorrow ? nil : model.current, now: model.now,
                           showMidnight: day == .both, selected: $scrubbed)
                    .frame(height: 170)
            }
        }
    }

    // MARK: Pieces

    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
    }

    private func cents(_ total: Double) -> String { PriceFormatter.menuBar(total, currency: model.data?.currency ?? "EUR", style: .cents) }

    private func bigNumber(_ total: Double, _ data: PriceData) -> String {
        switch model.labelStyle {
        case .cents: return PriceFormatter.menuBar(total, currency: data.currency, style: .cents).replacingOccurrences(of: PriceFormatter.centSymbol(for: data.currency), with: "")
        case .currency: return PriceFormatter.menuBar(total, currency: data.currency, style: .currency)
        case .plain: return PriceFormatter.menuBar(total, currency: data.currency, style: .plain)
        }
    }

    private func bigUnit(_ data: PriceData) -> String {
        switch model.labelStyle {
        case .cents: return "\(PriceFormatter.centSymbol(for: data.currency).trimmingCharacters(in: .whitespaces))/kWh"
        case .currency, .plain: return "/kWh"
        }
    }

    private func isTomorrow(_ slot: PricePoint?, _ data: PriceData) -> Bool {
        guard let slot else { return false }
        return !data.today.contains(slot)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Tibber").font(.headline)
            Text("Create a personal access token at developer.tibber.com (Settings → Access Token) and paste it in Settings. Prices then appear in the menu bar.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open developer.tibber.com") { NSWorkspace.shared.open(URL(string: "https://developer.tibber.com/settings/access-token")!) }
                Button("Settings…") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
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
            Button { Task { await model.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.isLoading || !model.hasToken).help("Refresh now")
            Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.borderless).help("Quit")
        }
    }
}

// MARK: - Building blocks

/// A rounded tile with the dashboard's quiet fill and an optional colored accent bar on the left.
struct Tile<Content: View>: View {
    var accent: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            if let accent {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3).padding(.vertical, 10)
            }
            content()
                .padding(.horizontal, accent == nil ? 14 : 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

/// Half-circle gauge for the live draw relative to today's peak.
struct PowerGauge: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.5)
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().trim(from: 0, to: 0.5 * fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .rotationEffect(.degrees(180))
        .frame(width: 52, height: 52)
        .frame(height: 30, alignment: .top)
        .clipped()
        .accessibilityLabel("Power gauge \(Int(fraction * 100)) percent of today's peak")
    }
}

enum TierColor {
    static func color(_ tier: PriceMath.RelativeTier?) -> Color {
        switch tier {
        case .cheap?: return .teal
        case .expensive?: return .orange
        case .normal?, nil: return .gray
        }
    }
    static func label(_ tier: PriceMath.RelativeTier) -> String {
        switch tier {
        case .cheap: return "Cheap"
        case .normal: return "Normal"
        case .expensive: return "Expensive"
        }
    }
}

enum LevelColor {
    static func color(_ level: PriceLevel?) -> Color {
        switch level {
        case .veryCheap?: return .green
        case .cheap?: return .teal
        case .normal?, nil: return .gray
        case .expensive?: return .orange
        case .veryExpensive?: return .red
        }
    }
}

/// Short "x min ago" helper for the footer.
enum Age {
    static func text(from date: Date, to now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "just now" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        return h < 24 ? "\(h) h ago" : "\(h / 24) d ago"
    }
}

extension PriceFormatter {
    static func currencyAmount(_ value: Double, currency: String, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

/// Bars colored relative to the day's average; past slots dimmed. Hover shows a slot in the capsule,
/// dragging also moves the price tile, and releasing snaps back to the current slot.
struct PriceChart: View {
    let points: [PricePoint]
    let data: PriceData
    let current: PricePoint?
    let now: Date
    let showMidnight: Bool
    @Binding var selected: PricePoint?
    @State private var hovered: PricePoint?

    private var resolution: Resolution { data.resolution }
    private var timeZone: TimeZone { data.timeZone }
    private var average: Double { PriceMath.stats(points)?.average ?? 0 }
    private var marker: PricePoint? { selected ?? hovered ?? current }
    private var markerDate: Date? {
        if let slot = selected ?? hovered { return slot.startsAt.addingTimeInterval(resolution.slotLength / 2) }
        return current == nil ? nil : now
    }
    private var markerIsCurrent: Bool { selected == nil && hovered == nil }

    var body: some View {
        if points.isEmpty {
            Text("No prices for this day yet").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    RectangleMark(
                        xStart: .value("Start", p.startsAt.addingTimeInterval(resolution.slotLength * 0.02)),
                        xEnd: .value("End", p.startsAt.addingTimeInterval(resolution.slotLength * 0.98)),
                        yStart: .value("Floor", yDomain.lowerBound),
                        yEnd: .value("Price", p.total * 100)
                    )
                    .foregroundStyle(barColor(p))
                }
                if showMidnight, let midnight = data.tomorrow.first?.startsAt {
                    RuleMark(x: .value("Midnight", midnight))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                if let marker, let markerDate {
                    RuleMark(x: .value("Marker", markerDate))
                        .lineStyle(StrokeStyle(lineWidth: selected == nil ? 1 : 1.5))
                        .foregroundStyle(.primary.opacity(0.6))
                        .annotation(position: .top, alignment: .center) {
                            Text(markerIsCurrent ? String(format: "%.1f", marker.total * 100)
                                 : "\(String(format: "%.1f", marker.total * 100)) · \(PriceFormatter.time(marker.startsAt, timeZone: timeZone))")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(markerIsCurrent ? AnyShapeStyle(TierColor.color(.cheap)) : AnyShapeStyle(.regularMaterial), in: Capsule())
                                .foregroundStyle(markerIsCurrent ? Color.black.opacity(0.85) : Color.primary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: points.count > 100 ? 6 : 3)) { value in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.14))
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(PriceFormatter.time(d, timeZone: timeZone)).font(.system(size: 9)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.14))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(String(format: "%.0f", v)).font(.system(size: 9)) }
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard selected == nil, let plot = proxy.plotFrame else { return }
                                let x = location.x - geo[plot].origin.x
                                if let date: Date = proxy.value(atX: x) { hovered = slot(at: date) }
                            case .ended:
                                hovered = nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plot = proxy.plotFrame else { return }
                                    let x = value.location.x - geo[plot].origin.x
                                    if let date: Date = proxy.value(atX: x) { selected = slot(at: date) }
                                }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
        }
    }

    private var xDomain: ClosedRange<Date> {
        let start = points.first!.startsAt
        let end = points.last!.startsAt.addingTimeInterval(resolution.slotLength)
        return start...end
    }

    /// Cents, padded to the nearest 5 around the day's range so the bars use the full height.
    private var yDomain: ClosedRange<Double> {
        guard let s = PriceMath.stats(points) else { return 0...40 }
        let lo = (floor((s.min.total * 100 - 2) / 5) * 5)
        let hi = (ceil((s.max.total * 100 + 2) / 5) * 5)
        return min(lo, hi - 5)...max(hi, lo + 5)
    }

    private func slot(at date: Date) -> PricePoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if date <= first.startsAt { return first }
        if date >= last.startsAt { return last }
        return points.last { $0.startsAt <= date }
    }

    private func barColor(_ p: PricePoint) -> Color {
        let base = TierColor.color(PriceMath.relativeTier(p.total, average: average))
        if let marker, marker.startsAt == p.startsAt { return base }
        let isPast = p.startsAt.addingTimeInterval(resolution.slotLength) <= now
        return base.opacity(isPast ? 0.5 : 0.85)
    }
}
