import XCTest
import SwiftUI
@testable import Metroneo

/// The `Color` ⇄ `#RRGGBBAA` bridge behind the performance-color **ColorPicker**
/// (D10). The picker binds a `Color`; a pick is serialized to hex for storage, and
/// stored hex is shown back as a `Color`. These assert the round-trip is stable —
/// including opacity — so a chosen color persists and reloads unchanged.
final class ColorPickerBridgeTests: XCTestCase {

    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    func testHexToColorToHexRoundTrips() { // spec: CLR-04
        for hex in ["#1B5E20FF", "#123456CC", "#FF0000FF", "#00FF0080", "#0000FFFF"] {
            let rgba = ColorHex.parse(hex)!
            let backHex = ColorHex.string(Color(rgba).rgbaComponents)
            XCTAssertEqual(backHex, hex, "\(hex) should round-trip through Color unchanged (incl. alpha)")
        }
    }

    func testPickedColorPersistsThroughServiceAndReloads() { // spec: CLR-04 (integration)
        let d = makeDefaults()
        let s = PerformanceCustomizationService(defaults: d)

        // Mirrors the ColorPicker binding's setter: Color → hex → store.
        let picked = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8)
        s.setHex(ColorHex.string(picked.rgbaComponents), for: .good)

        // A fresh service (reload from the same store) shows the same color back.
        let reloaded = PerformanceCustomizationService(defaults: d)
        let shown = reloaded.color(for: .good).rgbaComponents
        let target = picked.rgbaComponents
        XCTAssertEqual(shown.r, target.r, accuracy: 1.0 / 255, "red round-trips")
        XCTAssertEqual(shown.g, target.g, accuracy: 1.0 / 255, "green round-trips")
        XCTAssertEqual(shown.b, target.b, accuracy: 1.0 / 255, "blue round-trips")
        XCTAssertEqual(shown.a, target.a, accuracy: 1.0 / 255, "opacity round-trips")
    }

    func testUnsetColorShowsPaletteDefault() { // spec: CLR-02
        let s = PerformanceCustomizationService(defaults: makeDefaults())
        // With no override, the picker's `get` returns the Palette default for the level.
        XCTAssertEqual(ColorHex.string(s.color(for: .excellent).rgbaComponents),
                       ColorHex.string(PerformanceLevel.excellent.color.rgbaComponents),
                       "unset → Palette default color")
    }
}
