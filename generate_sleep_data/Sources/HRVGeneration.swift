/// Purpose:
/// Pure request models for writing today's HRV data into Health.
///
/// Responsibilities:
/// Define the UI-facing mode and anomaly-oriented HRV presets, and combine
/// today's date with a chosen time into a concrete HRV sample timestamp.
///
/// Inputs and Outputs:
/// Inputs are the selected data mode, today's HRV record date, the chosen time,
/// and a preset value. Output is a single timestamp plus HRV value in
/// milliseconds that the HealthKit layer can persist.
///
/// Non-Goals:
/// This file does not render UI, request authorization, or talk to HealthKit.
import Foundation

enum HealthDataMode: String, CaseIterable, Identifiable {
    case sleep
    case hrv
    case restingHeartRate
    case workout
    case steps
    case menstrual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .hrv:
            return "HRV"
        case .restingHeartRate:
            return "静息心率"
        case .workout:
            return "锻炼"
        case .steps:
            return "步数"
        case .menstrual:
            return "经期"
        }
    }

    var navigationTitle: String {
        switch self {
        case .sleep:
            return "Sleep Data"
        case .hrv:
            return "HRV Data"
        case .restingHeartRate:
            return "静息心率数据"
        case .workout:
            return "锻炼数据"
        case .steps:
            return "步数数据"
        case .menstrual:
            return "经期数据"
        }
    }
}

enum HRVPreset: String, CaseIterable, Identifiable {
    case tooLow
    case tooHigh

    var id: String { rawValue }

    var segmentTitle: String {
        switch self {
        case .tooLow:
            return "过低"
        case .tooHigh:
            return "过高"
        }
    }

    var title: String {
        switch self {
        case .tooLow:
            return "过低"
        case .tooHigh:
            return "过高"
        }
    }

    var valueMilliseconds: Double {
        switch self {
        case .tooLow:
            return 12
        case .tooHigh:
            return 82
        }
    }

    /// The typical day-to-day swing around the baseline, in ms. Combined drift +
    /// jitter can occasionally reach roughly 1.4× this on a peak day.
    var variationMilliseconds: Double {
        switch self {
        case .tooLow:
            return 6
        case .tooHigh:
            return 16
        }
    }
}

struct HRVDaySample: Equatable {
    let date: Date
    let valueMilliseconds: Double
}

struct HRVWriteRequest: Equatable {
    var recordDate: Date
    var sampleTime: Date
    var preset: HRVPreset
    var days: Int = 1

    /// The baseline value for the selected level (before per-day variation).
    var valueMilliseconds: Double {
        preset.valueMilliseconds
    }

    /// The most-recent sample timestamp (the end of the range).
    func sampleDate(calendar: Calendar = .current) -> Date {
        calendar.combineHRVDate(
            date: calendar.startOfDay(for: recordDate),
            withTimeFrom: sampleTime
        )
    }

    /// One reading per day going back `days` from `recordDate`, each fluctuating
    /// around the level baseline so the trend never looks flat.
    func makeSamples(calendar: Calendar = .current) -> [HRVDaySample] {
        guard days > 0 else {
            return []
        }

        let endDay = calendar.startOfDay(for: recordDate)
        return (0..<days)
            .compactMap { offset -> HRVDaySample? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
                    return nil
                }

                let sampleDate = calendar.combineHRVDate(date: day, withTimeFrom: sampleTime)
                let seed = MockVariation.daySeed(for: day, calendar: calendar)

                // Combine a slow multi-week drift with two faster octaves and a
                // little daily jitter so the trend rises and falls instead of just
                // jittering around a flat line.
                let position = Double(seed)
                let drift = MockVariation.smoothNoise(position / 23) * 0.6
                    + MockVariation.smoothNoise(position / 9 + 100) * 0.35
                    + MockVariation.smoothNoise(position / 4 + 250) * 0.2
                let jitter = MockVariation.signedNoise(seed &* 31 &+ 7) * 0.25
                let value = max(1, (preset.valueMilliseconds + (drift + jitter) * preset.variationMilliseconds).rounded())
                return HRVDaySample(date: sampleDate, valueMilliseconds: value)
            }
            .sorted { $0.date < $1.date }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> HRVWriteRequest {
        HRVWriteRequest(
            recordDate: calendar.startOfDay(for: now),
            sampleTime: now,
            preset: .tooLow,
            days: 1
        )
    }
}

enum HRVRangePreset: String, CaseIterable, Identifiable {
    case today
    case lastWeek
    case lastMonth
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "仅今天"
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
        case .today:
            return "只写入今天 1 条 HRV"
        case .lastWeek:
            return "最近 7 天，每天 1 条，围绕所选档位波动"
        case .lastMonth:
            return "最近 30 天，每天 1 条，适合补一个月的 HRV 趋势"
        case .lastYear:
            return "最近 365 天，每天 1 条，一次性补满整年的 HRV 趋势"
        }
    }

    var days: Int {
        switch self {
        case .today:
            return 1
        case .lastWeek:
            return 7
        case .lastMonth:
            return 30
        case .lastYear:
            return 365
        }
    }

    func apply(
        to request: inout HRVWriteRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        request.recordDate = calendar.startOfDay(for: now)
        request.days = days
    }
}

private extension Calendar {
    func combineHRVDate(date: Date, withTimeFrom time: Date) -> Date {
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
