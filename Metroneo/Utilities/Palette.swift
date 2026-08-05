import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App color palette and shared surface styling. Replaces the old hex-string
/// parsing: performance colors are `Color` constants (saturated fills that read
/// well with white text in both light and dark mode), and surfaces use adaptive
/// system colors so the UI is correct in dark mode.
extension PerformanceLevel {
    /// Fill color for this level; pairs with white text.
    var color: Color {
        switch self {
        case .excellent: return Color(red: 0.18, green: 0.49, blue: 0.20) // green 800
        case .veryGood:  return Color(red: 0.30, green: 0.69, blue: 0.31) // green 500
        case .good:      return Color(red: 0.13, green: 0.59, blue: 0.95) // blue 500
        case .fair:      return Color(red: 1.00, green: 0.60, blue: 0.00) // orange 500
        case .poor:      return Color(red: 0.96, green: 0.26, blue: 0.21) // red 500
        }
    }
}

extension PerformancePreferencesService {
    /// Fill color for a rating, classified against the current cutoffs.
    func color(for rating: Int) -> Color { level(for: rating).color }
}

extension Color {
    init(_ rgba: ColorHex.RGBA) {
        self = Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    /// The color's **sRGB** components, for persistence as `#RRGGBBAA` (D10). A
    /// color picked in any space (e.g. Display P3 from the system picker) is
    /// converted to sRGB so it round-trips with ``init(_:)`` and ``ColorHex``.
    var rgbaComponents: ColorHex.RGBA {
        #if canImport(UIKit)
        let cg = UIColor(self).cgColor
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cg.converted(to: srgb, intent: .defaultIntent, options: nil),
           let c = converted.components, c.count >= 3 {
            return ColorHex.RGBA(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]), a: Double(converted.alpha))
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return ColorHex.RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        #else
        return ColorHex.RGBA(r: 0, g: 0, b: 0, a: 1)
        #endif
    }
}

extension PerformanceCustomizationService {
    /// The level's fill — the custom `#RRGGBBAA` if set, else the Palette default (D10).
    func color(for level: PerformanceLevel) -> Color {
        if let hex = hex(for: level), let rgba = ColorHex.parse(hex) { return Color(rgba) }
        return level.color
    }

    /// Black-vs-white badge text for the level's fill, by WCAG contrast (D10.5).
    /// The default Palette fills are saturated and pair with white.
    func textColor(for level: PerformanceLevel) -> Color {
        if let hex = hex(for: level), let rgba = ColorHex.parse(hex) {
            return ColorHex.preferBlackText(onFill: rgba) ? .black : .white
        }
        return .white
    }
}

extension View {
    /// The standard rounded, bordered "card" surface used across the app.
    /// Uses adaptive system colors, so it renders correctly in dark mode.
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color(.separator)))
    }
}
