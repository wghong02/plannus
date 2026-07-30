import Foundation

/// Pure color helpers for the customizable performance-level colors (D10).
/// No SwiftUI — parses/serializes `#RRGGBBAA` and picks black-vs-white text by
/// WCAG contrast (D10.5), so it stays directly unit-testable (CLR-01, CLR-03).
public enum ColorHex {
    public struct RGBA: Equatable, Sendable {
        public var r: Double, g: Double, b: Double, a: Double // each 0...1
        public init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
    }

    /// Parses `#RRGGBBAA` (also accepts `#RRGGBB`, alpha ⇒ FF). `nil` when malformed.
    public static func parse(_ hex: String) -> RGBA? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        let chars = Array(s)
        func byte(_ i: Int) -> Double {
            let pair = String(chars[i * 2]) + String(chars[i * 2 + 1])
            return Double(Int(pair, radix: 16) ?? 0) / 255.0
        }
        return RGBA(r: byte(0), g: byte(1), b: byte(2), a: s.count == 8 ? byte(3) : 1.0)
    }

    /// Serializes to uppercase `#RRGGBBAA` (round-trips with ``parse(_:)``).
    public static func string(_ c: RGBA) -> String {
        func hx(_ v: Double) -> String { String(format: "%02X", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#\(hx(c.r))\(hx(c.g))\(hx(c.b))\(hx(c.a))"
    }

    /// WCAG 2.x relative luminance of the (opaque) color.
    public static func relativeLuminance(_ c: RGBA) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast ratio between two relative luminances.
    public static func contrastRatio(_ l1: Double, _ l2: Double) -> Double {
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Picks black vs white text for a fill by whichever gives the higher WCAG
    /// contrast (D10.5). Returns `true` for **black** text.
    public static func preferBlackText(onFill fill: RGBA) -> Bool {
        let bg = relativeLuminance(fill)
        return contrastRatio(bg, 0.0) >= contrastRatio(bg, 1.0)
    }
}
