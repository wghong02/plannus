import SwiftUI

/// Key for the first-run onboarding "seen" flag (D13.2).
let onboardingSeenKey = "@onboarding_seen"

/// Settings tab (DESIGN.md §9, v2). Personal Preferences → the combined
/// **Performance customization** screen (cutoffs + labels + colors + trend,
/// D8/D10/D12); About/version; a tutorial replay (D13.3); and, in Debug builds,
/// entry-store management.
struct SettingsView: View {
    let database: EntryDatabase

    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var seriesService: SeriesService
    @AppStorage(onboardingSeenKey) private var onboardingSeen = false
    @State private var alert: SettingsAlert?

    private struct SettingsAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version).\(build)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Personal Preferences") {
                    NavigationLink("Performance") { PerformanceCustomizationScreen() }
                        .accessibilityIdentifier("performanceSettingsLink")
                }

                Section("Help") {
                    Button("Show Tutorial Again") { onboardingSeen = false }
                }

                #if DEBUG
                Section("Database Management") {
                    Button("Database Stats") {
                        let s = database.stats()
                        alert = SettingsAlert(title: "Database Stats",
                                              message: "Entries: \(s.entryCount)\nCollections: \(s.collectionCount)\nSeries: \(s.seriesCount)\nSchema: v\(s.schemaVersion)")
                    }
                    Button("Erase All Data", role: .destructive) {
                        try? database.reset()
                        // Refresh the in-memory caches so the UI doesn't keep
                        // showing (and re-persisting) the erased rows.
                        entryService.loadEntries()
                        collectionService.loadCollections()
                        seriesService.loadSeries()
                        alert = SettingsAlert(title: "Success", message: "All data has been cleared.")
                    }
                }
                #endif

                Section("About") {
                    HStack { Text("Version"); Spacer(); Text(Self.appVersion).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
        }
    }
}

/// The single "Performance customization" screen (D8/D10/D12 consolidated).
struct PerformanceCustomizationScreen: View {
    @EnvironmentObject private var preferences: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var fair = 0
    @State private var good = 0
    @State private var veryGood = 0
    @State private var excellent = 0
    @State private var cutoffAlert: String?

    var body: some View {
        Form {
            Section("Cutoffs") {
                cutoffRow("Fair", value: $fair)
                cutoffRow("Good", value: $good)
                cutoffRow("Very Good", value: $veryGood)
                cutoffRow("Excellent", value: $excellent)
                Button("Save Cutoffs") { saveCutoffs() }
            }

            Section("Labels & Colors") {
                ForEach(PerformanceLevel.allCases, id: \.self) { level in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(level.defaultLabel, text: labelBinding(level))
                            .accessibilityIdentifier("label-\(level.key)")
                        ColorPicker("Color", selection: colorBinding(level), supportsOpacity: true)
                            .accessibilityIdentifier("color-\(level.key)")
                    }
                }
            }

            Section("Overall Trend") {
                Stepper("Improving ≥ \(Int(custom.trendImprovingPercent))%", value: trendBinding(improving: true), in: 0...100)
                Stepper("Declining ≤ \(Int(custom.trendDecliningPercent))%", value: trendBinding(improving: false), in: -100...0)
                TextField("Improving", text: trendLabelBinding(\.improving, default: "Improving"))
                TextField("Neutral", text: trendLabelBinding(\.neutral, default: "Neutral"))
                TextField("Declining", text: trendLabelBinding(\.declining, default: "Declining"))
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    preferences.resetToDefaults()
                    custom.resetToDefaults()
                    seed()
                }
            }
        }
        .navigationTitle("Performance")
        .onAppear(perform: seed)
        .alert("Invalid Cutoffs", isPresented: Binding(get: { cutoffAlert != nil }, set: { if !$0 { cutoffAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(cutoffAlert ?? "") }
    }

    private func cutoffRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                .accessibilityIdentifier("cutoff-\(label)")
        }
    }

    private func seed() {
        let c = preferences.cutoffs
        fair = c.fair; good = c.good; veryGood = c.veryGood; excellent = c.excellent
    }

    private func saveCutoffs() {
        guard [fair, good, veryGood, excellent].allSatisfy({ (0...100).contains($0) }) else {
            cutoffAlert = "Each threshold must be between 0 and 100."; return
        }
        guard fair <= good, good <= veryGood, veryGood <= excellent else {
            cutoffAlert = "Thresholds must not decrease: Fair ≤ Good ≤ Very Good ≤ Excellent."; return
        }
        preferences.setCutoffs(PerformanceCutoffs(fair: fair, good: good, veryGood: veryGood, excellent: excellent))
    }

    // MARK: - Bindings into the customization service

    private func labelBinding(_ level: PerformanceLevel) -> Binding<String> {
        Binding(
            get: { custom.customization.labels[level.key] ?? "" },
            set: { custom.setLabel($0, for: level) }
        )
    }

    /// Binds the level's fill to a `ColorPicker` (D10): the picker shows the
    /// current effective color (custom override or Palette default), and a pick is
    /// persisted as `#RRGGBBAA`.
    private func colorBinding(_ level: PerformanceLevel) -> Binding<Color> {
        Binding(
            get: { custom.color(for: level) },
            set: { custom.setHex(ColorHex.string($0.rgbaComponents), for: level) }
        )
    }

    private func trendBinding(improving: Bool) -> Binding<Double> {
        Binding(
            get: { improving ? custom.trendImprovingPercent : custom.trendDecliningPercent },
            set: { custom.setTrendThresholds(
                improving: improving ? $0 : custom.trendImprovingPercent,
                declining: improving ? custom.trendDecliningPercent : $0
            ) }
        )
    }

    private func trendLabelBinding(_ keyPath: WritableKeyPath<TrendLabels, String>, default def: String) -> Binding<String> {
        Binding(
            get: { custom.customization.trendLabels[keyPath: keyPath] },
            set: { newValue in
                var labels = custom.customization.trendLabels
                labels[keyPath: keyPath] = newValue
                custom.setTrendLabels(labels)
            }
        )
    }
}
