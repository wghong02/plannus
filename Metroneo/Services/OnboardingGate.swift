import Foundation

/// First-run onboarding flag (D13.2). Extracted from the view so the
/// **show-once / replay** semantics are directly unit-testable (TUT-01/TUT-02)
/// rather than trapped in a `fullScreenCover`.
public enum OnboardingGate {
    /// First-run "seen" flag key (D13.2); also the `@AppStorage`/launch-arg name.
    public static let seenKey = "@onboarding_seen"

    /// Whether the walkthrough should appear (D13.1): true until it's been seen.
    public static func shouldShow(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: seenKey)
    }

    /// Marks the walkthrough seen so it doesn't reappear (D13.2).
    public static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seenKey)
    }

    /// Re-arms the walkthrough (Settings → "Show Tutorial Again", D13.3).
    public static func replay(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: seenKey)
    }
}
