import SwiftUI
import Charts
import TibberCore

struct PopoverView: View {
    @ObservedObject var model: PriceModel
    /// Slot under the pointer while dragging across the chart; nil shows the current slot again.
    @State private var scrubbed: PricePoint?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.hasToken {
                onboarding
            } else if let data = model.data {
                header(data)
                if model.liveSupported && model.showLivePower { liveRow(data) }
                PriceChart(data: data, current: model.current, now: model.now, selected: $scrubbed)
                    .frame(height: 160)
                statsRow(data)
                plannerRow(data)
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
        .padding(12)
        .frame(width: 420)
    }

    // MARK: Header

    private func header(_ data: PriceData) -> some View {
        let shown = scrubbed ?? model.current
        let isTomorrow = shown.map { !data.today.contains($0) } ?? false
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let slot = shown {
                    Text(PriceFormatter.detailed(slot.total, currency: data.currency)).font(.system(size: 22, weight: .semibold, design: .rounded))
                    HStack(spacing: 6) {
                        Text(PriceFormatter.slotRange(slot, slotLength: data.resolution.slotLength, timeZone: data.timeZone))
                        if scrubbed != nil { Text(isTomorrow ? "tomorrow" : "selected").font(.caption2).foregroundStyle(.tertiary) }
                        if let level = slot.level {
                            Text(level.label)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(LevelColor.color(level).opacity(0.2), in: Capsule())
                                .foregroundStyle(LevelColor.color(level))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No price for this moment").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(data.home.displayName).font(.caption.weight(.medium))
                if scrubbed == nil, let current = model.current, let next = data.next(after: current.startsAt) {
                    Text("next \(PriceFormatter.menuBar(next.total, currency: data.currency, style: model.labelStyle)) \(model.trend?.arrow ?? "")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func liveRow(_ data: PriceData) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg").foregroundStyle(.secondary)
            if let live = model.freshLive ?? model.live {
                let stale = model.freshLive == nil
                Text(LiveMeasurement.formatPower(live.power)).font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(stale ? .secondary : .primary)
                Text("now").font(.caption2).foregroundStyle(.tertiary)
                if let kwh = live.accumulatedConsumption {
                    Text("· today \(String(format: "%.1f", kwh)) kWh").font(.caption).foregroundStyle(.secondary)
                }
                if let cost = live.accumulatedCost {
                    Text("· \(PriceFormatter.currencyAmount(cost, currency: live.currency ?? data.currency))").font(.caption).foregroundStyle(.secondary)
                }
                if stale { Text("(stale)").font(.caption2).foregroundStyle(.orange) }
            } else {
                Text(liveStatusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var liveStatusText: String {
        switch model.liveStatus {
        case .idle: return "Live power off"
        case .connecting: return "Connecting to Pulse…"
        case .connected: return "Waiting for the first reading…"
        case .reconnecting(let s): return "Pulse stream lost, reconnecting in \(s) s"
        case .failed(let why): return "Pulse stream failed: \(why)"
        }
    }

    // MARK: Stats & planner

    private func statsRow(_ data: PriceData) -> some View {
        let stats = PriceMath.stats(data.today)
        return HStack {
            if let s = stats {
                stat("Low today", s.min.total, data, at: s.min.startsAt)
                Spacer()
                stat("Avg", s.average, data, at: nil)
                Spacer()
                stat("High today", s.max.total, data, at: s.max.startsAt)
            }
            if let t = PriceMath.stats(data.tomorrow) {
                Spacer()
                stat("Tomorrow", t.average, data, at: nil, note: "\(PriceFormatter.menuBar(t.min.total, currency: data.currency, style: model.labelStyle))–\(PriceFormatter.menuBar(t.max.total, currency: data.currency, style: model.labelStyle))")
            }
        }
    }

    private func stat(_ title: String, _ value: Double, _ data: PriceData, at: Date?, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(PriceFormatter.menuBar(value, currency: data.currency, style: model.labelStyle)).font(.caption.weight(.medium))
                if let at { Text(PriceFormatter.time(at, timeZone: data.timeZone)).font(.caption2).foregroundStyle(.secondary) }
                if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func plannerRow(_ data: PriceData) -> some View {
        HStack(spacing: 6) {
            Text("Cheapest").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { model.notificationPrefs.plannerHours }, set: { model.notificationPrefs.plannerHours = $0 })) {
                ForEach(Planner.durationsHours, id: \.self) { Text("\($0) h").tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 64)
            if let w = model.plannedWindow {
                let tomorrow = !data.today.contains { $0.startsAt == w.start }
                Text("\(PriceFormatter.time(w.start, timeZone: data.timeZone))–\(PriceFormatter.time(w.end, timeZone: data.timeZone))\(tomorrow ? " tomorrow" : "") · avg \(PriceFormatter.menuBar(w.average, currency: data.currency, style: model.labelStyle))")
                    .font(.caption)
            } else {
                Text("no window in range").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(get: { model.notificationPrefs.cheapWindowStart }, set: { model.notificationPrefs.cheapWindowStart = $0 })) {
                Image(systemName: model.notificationPrefs.cheapWindowStart ? "bell.fill" : "bell")
            }
            .toggleStyle(.button).buttonStyle(.borderless).controlSize(.small)
            .help("Notify me 10 minutes before this window starts")
        }
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

/// One continuous strip: today and, once published, tomorrow. Hover shows a slot's price in the
/// capsule; dragging also moves the header, and releasing snaps back to the current slot.
struct PriceChart: View {
    let data: PriceData
    let current: PricePoint?
    let now: Date
    @Binding var selected: PricePoint?
    @State private var hovered: PricePoint?

    private var points: [PricePoint] { data.all }
    private var resolution: Resolution { data.resolution }
    private var timeZone: TimeZone { data.timeZone }
    private var stats: PriceStats? { PriceMath.stats(points) }
    /// The slot the marker sits on: scrubbed, else hovered, else current.
    private var marker: PricePoint? { selected ?? hovered ?? current }
    private var markerDate: Date? {
        if let slot = selected ?? hovered { return slot.startsAt.addingTimeInterval(resolution.slotLength / 2) }
        return current == nil ? nil : now
    }
    private var midnight: Date? { data.tomorrow.first?.startsAt }

    var body: some View {
        if points.isEmpty {
            Text("No prices yet").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    BarMark(
                        xStart: .value("Start", p.startsAt.addingTimeInterval(resolution.slotLength * 0.08)),
                        xEnd: .value("End", p.startsAt.addingTimeInterval(resolution.slotLength * 0.92)),
                        y: .value("Price", p.total * 100)
                    )
                    .foregroundStyle(barColor(p))
                }
                if let s = PriceMath.stats(data.today) {
                    RuleMark(y: .value("Average", s.average * 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                if let midnight {
                    RuleMark(x: .value("Midnight", midnight))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, alignment: .leading) {
                            Text("tomorrow").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                }
                if let marker, let markerDate {
                    RuleMark(x: .value("Marker", markerDate))
                        .lineStyle(StrokeStyle(lineWidth: selected == nil ? 1 : 1.5))
                        .foregroundStyle(.primary.opacity(0.7))
                        .annotation(position: .top, alignment: .center) {
                            Text(marker.startsAt == current?.startsAt && selected == nil && hovered == nil
                                 ? String(format: "%.1f", marker.total * 100)
                                 : "\(String(format: "%.1f", marker.total * 100)) · \(PriceFormatter.time(marker.startsAt, timeZone: timeZone))")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: data.hasTomorrow ? 6 : 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(PriceFormatter.time(d, timeZone: timeZone)).font(.system(size: 9)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(String(format: "%.0f", v)).font(.system(size: 9)) }
                    }
                }
            }
            .chartXScale(domain: xDomain)
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

    /// The slot containing the given date, clamped to the chart's range.
    private func slot(at date: Date) -> PricePoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if date <= first.startsAt { return first }
        if date >= last.startsAt { return last }
        return points.last { $0.startsAt <= date }
    }

    private func barColor(_ p: PricePoint) -> Color {
        let base = LevelColor.color(p.level)
        if let marker, marker.startsAt == p.startsAt { return base }
        return base.opacity(0.55)
    }
}
