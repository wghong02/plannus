import SwiftUI

/// A 0–100 slider paired with an editable number field bound to the same value
/// (D11). Dragging and typing stay in sync; typed input is clamped to 0–100, and
/// non-numeric/blank input falls back to the current value (D11.1/D11.2).
struct SliderField: View {
    let title: String
    @Binding var value: Int

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { _, newValue in
                        if let clamped = Self.clamp(newValue) { value = clamped }
                    }
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: 0...100, step: 1
            )
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in
            if Int(text) != newValue { text = String(newValue) }
        }
    }

    /// Parses typed input for the field (D11.2): clamps a number to 0–100, or
    /// returns `nil` for non-numeric/blank input (caller keeps the current value).
    static func clamp(_ text: String) -> Int? {
        guard let parsed = Int(text) else { return nil }
        return min(100, max(0, parsed))
    }
}
