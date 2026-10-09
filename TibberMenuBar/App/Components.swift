import SwiftUI
import AppKit
import TibberCore

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
        .accessibilityElement(children: .combine)
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
    static func color(_ tier: DisplayTier?, palette: PriceOptions.Palette) -> Color {
        Color(nsColor: nsColor(tier, palette: palette))
    }

    static func nsColor(_ tier: DisplayTier?, palette: PriceOptions.Palette) -> NSColor {
        switch (palette, tier) {
        case (.standard, .veryCheap?): return .systemGreen
        case (.standard, .cheap?): return .systemTeal
        case (.standard, .expensive?): return .systemOrange
        case (.standard, .veryExpensive?): return .systemRed
        // Okabe–Ito blues and oranges: distinguishable with the common kinds of color blindness.
        case (.colorblind, .veryCheap?): return NSColor(srgbRed: 0.000, green: 0.447, blue: 0.698, alpha: 1)
        case (.colorblind, .cheap?): return NSColor(srgbRed: 0.337, green: 0.706, blue: 0.914, alpha: 1)
        case (.colorblind, .expensive?): return NSColor(srgbRed: 0.902, green: 0.624, blue: 0.000, alpha: 1)
        case (.colorblind, .veryExpensive?): return NSColor(srgbRed: 0.835, green: 0.369, blue: 0.000, alpha: 1)
        case (_, .normal?), (_, nil): return .systemGray
        }
    }
}


/// Short "x min ago" helper for the footer.
enum Age {
    static func text(from date: Date, to now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return String(localized: "just now") }
        let m = Int(s / 60)
        if m < 60 { return String(localized: "\(m) min ago") }
        let h = m / 60
        return h < 24 ? String(localized: "\(h) h ago") : String(localized: "\(h / 24) d ago")
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
