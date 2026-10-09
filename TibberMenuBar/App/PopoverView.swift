import SwiftUI
import Charts
import TibberCore

struct PopoverView: View {
    @ObservedObject var model: PriceModel
    @State private var day: Day = .today
    /// Slot under the pointer while dragging across the chart; nil shows the current slot again.
    @State private var scrubbed: PricePoint?
    @Environment(\.openSettings) private var openSettings

    enum Day: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.hasToken {
                onboarding
            } else if let data = model.data {
                header(data)
                picker(data)
                PriceChart(points: day == .today ? data.today : data.tomorrow, resolution: data.resolution, timeZone: data.timeZone,
                           current: day == .today ? model.current : nil, now: model.now, selected: $scrubbed)
                    .frame(height: 150)
                statsRow(data)
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
        .frame(width: 340)
        .onAppear { if model.data?.hasTomorrow != true { day = .today } }
        .onChange(of: day) { _, _ in scrubbed = nil }
    }

    // MARK: Pieces

    private func header(_ data: PriceData) -> some View {
        let shown = scrubbed ?? model.current
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let current = shown {
                    Text(PriceFormatter.detailed(current.total, currency: data.currency)).font(.system(size: 22, weight: .semibold, design: .rounded))
                    HStack(spacing: 6) {
                        Text(PriceFormatter.slotRange(current, slotLength: data.resolution.slotLength, timeZone: data.timeZone))
                        if scrubbed != nil {
                            Text(day == .today ? "selected" : "tomorrow").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let level = current.level {
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
                if let next = model.current.flatMap({ data.next(after: $0.startsAt) }), day == .today {
                    Text("next \(PriceFormatter.menuBar(next.total, currency: data.currency, style: model.labelStyle))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func picker(_ data: PriceData) -> some View {
        Picker("", selection: $day) {
            Text("Today").tag(Day.today)
            Text(data.hasTomorrow ? "Tomorrow" : "Tomorrow (after 13:00)").tag(Day.tomorrow).disabled(!data.hasTomorrow)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!data.hasTomorrow)
    }

    private func statsRow(_ data: PriceData) -> some View {
        let points = day == .today ? data.today : data.tomorrow
        let stats = PriceMath.stats(points)
        let window = PriceMath.cheapestWindow(points, slots: Int(2 * 3600 / data.resolution.slotLength))
        return VStack(alignment: .leading, spacing: 3) {
            if let s = stats {
                HStack {
                    stat("Low", s.min.total, data, at: s.min.startsAt)
                    Spacer()
                    stat("Avg", s.average, data, at: nil)
                    Spacer()
                    stat("High", s.max.total, data, at: s.max.startsAt)
                }
            }
            if let w = window {
                Text("Cheapest 2 h from \(PriceFormatter.time(w.start.startsAt, timeZone: data.timeZone)) · avg \(PriceFormatter.menuBar(w.average, currency: data.currency, style: model.labelStyle))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ title: String, _ value: Double, _ data: PriceData, at: Date?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(PriceFormatter.menuBar(value, currency: data.currency, style: model.labelStyle)).font(.caption.weight(.medium))
                if let at { Text(PriceFormatter.time(at, timeZone: data.timeZone)).font(.caption2).foregroundStyle(.secondary) }
            }
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
            if let error = model.lastError, model.data != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)
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

struct PriceChart: View {
    let points: [PricePoint]
    let resolution: Resolution
    let timeZone: TimeZone
    let current: PricePoint?
    let now: Date
    @Binding var selected: PricePoint?

    private var stats: PriceStats? { PriceMath.stats(points) }
    /// The slot the marker sits on: the scrubbed one while dragging, otherwise the current one.
    private var marker: PricePoint? { selected ?? current }
    private var markerDate: Date? {
        if let selected { return selected.startsAt.addingTimeInterval(resolution.slotLength / 2) }
        return current == nil ? nil : now
    }

    var body: some View {
        if points.isEmpty {
            Text("No prices for this day yet").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    BarMark(
                        xStart: .value("Start", p.startsAt.addingTimeInterval(resolution.slotLength * 0.06)),
                        xEnd: .value("End", p.startsAt.addingTimeInterval(resolution.slotLength * 0.94)),
                        y: .value("Price", p.total * 100)
                    )
                    .foregroundStyle(barColor(p))
                }
                if let s = stats {
                    RuleMark(y: .value("Average", s.average * 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                if let marker, let markerDate {
                    RuleMark(x: .value("Marker", markerDate))
                        .lineStyle(StrokeStyle(lineWidth: selected == nil ? 1 : 1.5))
                        .foregroundStyle(.primary.opacity(0.7))
                        .annotation(position: .top, alignment: .center) {
                            Text(selected == nil
                                 ? String(format: "%.1f", marker.total * 100)
                                 : "\(String(format: "%.1f", marker.total * 100)) · \(PriceFormatter.time(marker.startsAt, timeZone: timeZone))")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
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
