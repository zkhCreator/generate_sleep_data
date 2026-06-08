/// Purpose:
/// Deterministic, well-distributed pseudo-random noise used to give generated
/// health data natural day-to-day variation while staying fully reproducible.
///
/// Responsibilities:
/// Hash an integer seed into a stable value, expose signed/unsigned helpers, and
/// derive a stable per-calendar-day seed so the same date always varies the same
/// way regardless of how the batch was requested.
///
/// Non-Goals:
/// This is not a cryptographic RNG and must not be used for anything other than
/// shaping mock data.
import Foundation

enum MockVariation {
    /// Well-distributed noise in [0, 1) for a given integer seed (splitmix64).
    static func unitNoise(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= (x >> 31)
        return Double(x % 1_000_000) / 1_000_000.0
    }

    /// Signed noise in [-1, 1) for a given integer seed.
    static func signedNoise(_ seed: Int) -> Double {
        unitNoise(seed) * 2 - 1
    }

    /// A stable per-calendar-day seed so a given date always varies identically.
    static func daySeed(for date: Date, calendar: Calendar) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }
}
