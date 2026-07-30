import Foundation

/// Pure Overall-Trend classification (D12 / TRND-01). The relative-change math
/// is unchanged from [PA-11]; only the two cutoffs become configurable. The
/// caller supplies the first vs last **non-empty** bucket averages and decides
/// "N/A" (fewer than 2 non-empty buckets).
public enum TrendClassifier {
    public enum Direction: Sendable, Equatable { case improving, neutral, declining }

    /// - Parameters:
    ///   - improvingPercent: relative-change cutoff for "improving" (default +5).
    ///   - decliningPercent: relative-change cutoff for "declining" (default −5).
    public static func classify(
        firstAverage: Double,
        lastAverage: Double,
        improvingPercent: Double,
        decliningPercent: Double
    ) -> Direction {
        // Zero-first special case, carried from [PA-11].
        guard firstAverage != 0 else {
            return lastAverage > 0 ? .improving : .neutral
        }
        let percentChange = (lastAverage - firstAverage) / firstAverage * 100
        if percentChange > improvingPercent { return .improving }
        if percentChange < decliningPercent { return .declining }
        return .neutral
    }
}
