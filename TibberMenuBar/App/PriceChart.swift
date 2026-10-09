import SwiftUI
import Charts
import TibberCore

/// Bars colored relative to the day's average; past slots dimmed. Hover shows a slot in the capsule,
/// dragging also moves the price tile, and releasing snaps back to the current slot.
struct PriceChart: View {
    let points: [PricePoint]
    let data: PriceData
    let current: PricePoint?
    let now: Date
    let showMidnight: Bool
    let options: ChartOptions
    let window: PlannedWindow?
    let tierFor: (PricePoint) -> DisplayTier
    @Binding var selected: PricePoint?
    @State private var hovered: PricePoint?
    private let accent = Color.teal

    private var resolution: Resolution { data.resolution }
    private var timeZone: TimeZone { data.timeZone }
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
                if options.shadeWindow, let w = window, w.end > points.first!.startsAt, w.start < xDomain.upperBound {
                    RectangleMark(
                        xStart: .value("Window start", max(w.start, xDomain.lowerBound)),
                        xEnd: .value("Window end", min(w.end, xDomain.upperBound)),
                        yStart: .value("Floor", yDomain.lowerBound),
                        yEnd: .value("Top", yDomain.upperBound)
                    )
                    .foregroundStyle(accent.opacity(0.12))
                }
                switch options.style {
                case .bars:
                    ForEach(points) { p in
                        RectangleMark(
                            xStart: .value("Start", p.startsAt.addingTimeInterval(resolution.slotLength * 0.02)),
                            xEnd: .value("End", p.startsAt.addingTimeInterval(resolution.slotLength * 0.98)),
                            yStart: .value("Floor", yDomain.lowerBound),
                            yEnd: .value("Price", p.total * 100)
                        )
                        .foregroundStyle(barColor(p))
                    }
                case .line, .area:
                    if options.style == .area {
                        ForEach(points) { p in
                            AreaMark(
                                x: .value("Time", p.startsAt.addingTimeInterval(resolution.slotLength / 2)),
                                yStart: .value("Floor", yDomain.lowerBound),
                                yEnd: .value("Price", p.total * 100)
                            )
                            .interpolationMethod(.stepCenter)
                            .foregroundStyle(lineColor.opacity(0.22))
                        }
                    }
                    ForEach(points) { p in
                        LineMark(
                            x: .value("Time", p.startsAt.addingTimeInterval(resolution.slotLength / 2)),
                            y: .value("Price", p.total * 100)
                        )
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .foregroundStyle(lineColor)
                    }
                    if options.colorMode == .tier {
                        ForEach(points.filter { tierFor($0) != .normal }) { p in
                            PointMark(
                                x: .value("Time", p.startsAt.addingTimeInterval(resolution.slotLength / 2)),
                                y: .value("Floor", yDomain.lowerBound)
                            )
                            .symbolSize(10)
                            .foregroundStyle(TierColor.color(tierFor(p)))
                        }
                    }
                }
                if options.showAverage, let s = PriceMath.stats(points) {
                    RuleMark(y: .value("Average", s.average * 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.6))
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
                            Text(verbatim: markerIsCurrent ? markerCents(marker)
                                 : "\(markerCents(marker)) · \(PriceFormatter.time(marker.startsAt, timeZone: timeZone))")
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

    /// Cents, padded to the nearest 5 around the day's range so the marks use the full height (or from zero).
    private func markerCents(_ p: PricePoint) -> String { (p.total * 100).formatted(.number.precision(.fractionLength(1))) }

    private var yDomain: ClosedRange<Double> {
        guard let s = PriceMath.stats(points) else { return 0...40 }
        let lo = options.fromZero ? min(0, floor(s.min.total * 100 / 5) * 5) : (floor((s.min.total * 100 - 2) / 5) * 5)
        let hi = (ceil((s.max.total * 100 + 2) / 5) * 5)
        return min(lo, hi - 5)...max(hi, lo + 5)
    }

    private var lineColor: Color { options.colorMode == .mono ? accent : Color.primary.opacity(0.85) }

    private func slot(at date: Date) -> PricePoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if date <= first.startsAt { return first }
        if date >= last.startsAt { return last }
        return points.last { $0.startsAt <= date }
    }

    private func barColor(_ p: PricePoint) -> Color {
        let base = options.colorMode == .tier ? TierColor.color(tierFor(p)) : accent
        if let marker, marker.startsAt == p.startsAt { return base }
        let isPast = options.dimPast && p.startsAt.addingTimeInterval(resolution.slotLength) <= now
        return base.opacity(isPast ? 0.45 : 0.85)
    }
}
