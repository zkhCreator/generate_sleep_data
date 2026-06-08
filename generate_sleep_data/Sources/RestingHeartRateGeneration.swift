/// Purpose:
/// Pure date-generation rules for a batch of synthetic daily resting heart rate
/// readings.
///
/// Responsibilities:
/// Turn a compact batch request (how many days back, average resting heart rate)
/// into concrete dated samples — one reading per day, fluctuating around the
/// baseline so the trend never looks flat — so the HealthKit layer can stay
/// focused on persistence.
///
/// Inputs and Outputs:
/// Inputs are the end date, the number of days to cover, the daily sample time,
/// and the average resting heart rate in BPM. Output is an ordered array of
/// `RestingHeartRateDaySample` values.
///
/// Non-Goals:
/// This file does not request permissions, import HealthKit, or render UI.
import Foundation

struct RestingHeartRateDaySample: Equatable {
    let date: Date
    let beatsPerMinute: Double
}

struct RestingHeartRateGenerationRequest: Equatable {
    var endDate: Date
    var sampleTime: Date
    var days: Int
    var averageBeatsPerMinute: Int

    /// One reading per day going back `days` from `endDate`, each fluctuating
    /// around the baseline so the trend rises and falls instead of jittering
    /// around a flat line.
    func makeSamples(calendar: Calendar = .current) -> [RestingHeartRateDaySample] {
        guard days > 0, averageBeatsPerMinute > 0 else {
            return []
        }

        let endDay = calendar.startOfDay(for: endDate)
        return (0..<days)
            .compactMap { offset -> RestingHeartRateDaySample? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
                    return nil
                }

                let sampleDate = calendar.combineRestingHeartRate(date: day, withTimeFrom: sampleTime)
                let seed = MockVariation.daySeed(for: day, calendar: calendar)

                // Combine a slow multi-week drift with two faster octaves and a
                // little daily jitter so the resting heart rate trend wanders
                // gently instead of staying flat.
                let position = Double(seed)
                let drift = MockVariation.smoothNoise(position / 23) * 0.6
                    + MockVariation.smoothNoise(position / 9 + 100) * 0.35
                    + MockVariation.smoothNoise(position / 4 + 250) * 0.2
                let jitter = MockVariation.signedNoise(seed &* 31 &+ 7) * 0.25
                let value = max(
                    30,
                    (Double(averageBeatsPerMinute) + (drift + jitter) * Self.variationBeatsPerMinute).rounded()
                )
                return RestingHeartRateDaySample(date: sampleDate, beatsPerMinute: value)
            }
            .sorted { $0.date < $1.date }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> RestingHeartRateGenerationRequest {
        RestingHeartRateGenerationRequest(
            endDate: calendar.startOfDay(for: now),
            sampleTime: now,
            days: 365,
            averageBeatsPerMinute: 62
        )
    }

    /// The typical day-to-day swing around the baseline, in BPM. Combined drift +
    /// jitter can occasionally reach roughly 1.4× this on a peak day.
    private static let variationBeatsPerMinute: Double = 5
}

enum RestingHeartRatePreset: String, CaseIterable, Identifiable {
    case lastWeek
    case lastMonth
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastWeek:
            return "最近 1 周"
        case .lastMonth:
            return "最近 1 个月"
        case .lastYear:
            return "一键 mock 1 年"
        }
    }

    var subtitle: String {
        switch self {
        case .lastWeek:
            return "最近 7 天，每天 1 条，静息心率约 62 次/分并逐日波动"
        case .lastMonth:
            return "最近 30 天，每天 1 条，适合补一个月的静息心率趋势"
        case .lastYear:
            return "最近 365 天，每天 1 条，一次性补满整年的静息心率趋势"
        }
    }

    var days: Int {
        switch self {
        case .lastWeek:
            return 7
        case .lastMonth:
            return 30
        case .lastYear:
            return 365
        }
    }

    func apply(
        to request: inout RestingHeartRateGenerationRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        request.endDate = calendar.startOfDay(for: now)
        request.days = days
    }
}

private extension Calendar {
    func combineRestingHeartRate(date: Date, withTimeFrom time: Date) -> Date {
        let dayComponents = dateComponents([.year, .month, .day], from: date)
        let timeComponents = dateComponents([.hour, .minute, .second], from: time)

        var combined = DateComponents()
        combined.year = dayComponents.year
        combined.month = dayComponents.month
        combined.day = dayComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second ?? 0

        return self.date(from: combined) ?? date
    }
}
