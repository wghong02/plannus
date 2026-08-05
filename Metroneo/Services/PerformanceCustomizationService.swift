import Foundation
import Combine

/// Editable strings for the Overall-Trend insight (D12).
public struct TrendLabels: Codable, Equatable, Sendable {
    public var improving: String
    public var neutral: String
    public var declining: String
    public var na: String

    public init(improving: String, neutral: String, declining: String, na: String) {
        self.improving = improving
        self.neutral = neutral
        self.declining = declining
        self.na = na
    }

    public static let defaults = TrendLabels(
        improving: "Improving", neutral: "Neutral", declining: "Declining", na: "N/A"
    )
}

/// Weights the analytics **average** by a reminder's priority (DESIGNV2 R7.3):
/// higher priority ⇒ higher weight, so important work counts more. Defaults
/// None/Low/Medium/High = 1/2/3/4; configurable in Settings.
public struct PriorityWeights: Codable, Equatable, Sendable {
    public var none: Int
    public var low: Int
    public var medium: Int
    public var high: Int

    public init(none: Int = 1, low: Int = 2, medium: Int = 3, high: Int = 4) {
        self.none = none
        self.low = low
        self.medium = medium
        self.high = high
    }

    public static let defaults = PriorityWeights()

    public func weight(for priority: ReminderPriority) -> Int {
        switch priority {
        case .none: return none
        case .low: return low
        case .medium: return medium
        case .high: return high
        }
    }
}

/// User overrides for the performance-level labels (D8), colors (D10), the
/// overall-trend thresholds/labels (D12), and the priority weights (R7.3). Stored
/// as user *overrides* only — anything unset falls back to the built-in default
/// (Palette color / English label / ±5% / 1·2·3·4), so defaults always equal
/// today's behavior (CLR-02).
public struct PerformanceCustomization: Codable, Equatable, Sendable {
    /// `PerformanceLevel.key` → custom label (blank/absent ⇒ default).
    public var labels: [String: String]
    /// `PerformanceLevel.key` → `#RRGGBBAA` (invalid/absent ⇒ Palette default).
    public var colorsHex: [String: String]
    public var trendImprovingPercent: Double
    public var trendDecliningPercent: Double
    public var trendLabels: TrendLabels
    public var priorityWeights: PriorityWeights

    public init(
        labels: [String: String] = [:],
        colorsHex: [String: String] = [:],
        trendImprovingPercent: Double = 5,
        trendDecliningPercent: Double = -5,
        trendLabels: TrendLabels = .defaults,
        priorityWeights: PriorityWeights = .defaults
    ) {
        self.labels = labels
        self.colorsHex = colorsHex
        self.trendImprovingPercent = trendImprovingPercent
        self.trendDecliningPercent = trendDecliningPercent
        self.trendLabels = trendLabels
        self.priorityWeights = priorityWeights
    }

    private enum CodingKeys: String, CodingKey {
        case labels, colorsHex, trendImprovingPercent, trendDecliningPercent, trendLabels, priorityWeights
    }

    /// Tolerant decode — a newly-added field (e.g. `priorityWeights`) defaults
    /// rather than failing the whole decode, so an upgrade never wipes stored prefs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        colorsHex = try c.decodeIfPresent([String: String].self, forKey: .colorsHex) ?? [:]
        trendImprovingPercent = try c.decodeIfPresent(Double.self, forKey: .trendImprovingPercent) ?? 5
        trendDecliningPercent = try c.decodeIfPresent(Double.self, forKey: .trendDecliningPercent) ?? -5
        trendLabels = try c.decodeIfPresent(TrendLabels.self, forKey: .trendLabels) ?? .defaults
        priorityWeights = try c.decodeIfPresent(PriorityWeights.self, forKey: .priorityWeights) ?? .defaults
    }

    public static let defaults = PerformanceCustomization()
}

public extension PerformanceLevel {
    /// Stable identity key — never the display string, which is user-editable (D8.1).
    var key: String {
        switch self {
        case .excellent: return "excellent"
        case .veryGood: return "veryGood"
        case .good: return "good"
        case .fair: return "fair"
        case .poor: return "poor"
        }
    }

    /// The built-in English label used when no custom one is set.
    var defaultLabel: String { rawValue }
}

/// Persists ``PerformanceCustomization`` under `@performance_customization` and
/// resolves each display value through its custom override, falling back to the
/// default when blank/unset — the same client-defaulted rule as D3 (D8.3, D10.2,
/// D12.2). Sits alongside ``PerformancePreferencesService`` (cutoffs), same
/// `UserDefaults`.
public final class PerformanceCustomizationService: ObservableObject {
    public static let storageKey = "@performance_customization"

    @Published public private(set) var customization: PerformanceCustomization

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(PerformanceCustomization.self, from: data) {
            self.customization = stored
        } else {
            self.customization = .defaults
        }
    }

    public func setCustomization(_ new: PerformanceCustomization) {
        customization = new
        if let data = try? JSONEncoder().encode(new) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    public func resetToDefaults() { setCustomization(.defaults) }

    // MARK: - Labels (D8)

    /// The level's display label — the custom one, or the default when blank (D8.3).
    public func label(for level: PerformanceLevel) -> String {
        let custom = customization.labels[level.key]?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? level.defaultLabel : custom
    }

    public func setLabel(_ text: String, for level: PerformanceLevel) {
        var c = customization
        c.labels[level.key] = text
        setCustomization(c)
    }

    // MARK: - Colors (D10)

    /// The user's `#RRGGBBAA` for the level, or `nil` when unset/invalid (⇒ the
    /// caller uses the Palette default, so defaults equal today's colors).
    public func hex(for level: PerformanceLevel) -> String? {
        guard let value = customization.colorsHex[level.key], ColorHex.parse(value) != nil else { return nil }
        return value
    }

    public func setHex(_ hex: String?, for level: PerformanceLevel) {
        var c = customization
        c.colorsHex[level.key] = hex
        setCustomization(c)
    }

    // MARK: - Overall trend (D12)

    public var trendImprovingPercent: Double { customization.trendImprovingPercent }
    public var trendDecliningPercent: Double { customization.trendDecliningPercent }

    public func setTrendThresholds(improving: Double, declining: Double) {
        var c = customization
        c.trendImprovingPercent = improving
        c.trendDecliningPercent = declining
        setCustomization(c)
    }

    public func setTrendLabels(_ labels: TrendLabels) {
        var c = customization
        c.trendLabels = labels
        setCustomization(c)
    }

    /// Resolves a trend label with the blank → default fallback (D12.2).
    public func trendLabel(_ keyPath: KeyPath<TrendLabels, String>) -> String {
        let custom = customization.trendLabels[keyPath: keyPath].trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? TrendLabels.defaults[keyPath: keyPath] : custom
    }

    // MARK: - Priority weights (R7.3)

    public var priorityWeights: PriorityWeights { customization.priorityWeights }

    public func setPriorityWeights(_ weights: PriorityWeights) {
        var c = customization
        c.priorityWeights = weights
        setCustomization(c)
    }
}
