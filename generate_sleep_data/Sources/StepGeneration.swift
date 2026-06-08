/// Purpose:
/// Pure date-generation rules for a batch of synthetic daily step counts.
///
/// Responsibilities:
/// Turn a compact batch request (how many days back, average steps per day) into
/// concrete dated, non-overlapping hourly step samples that sum to a believable
/// daily total, so the HealthKit layer can stay focused on persistence.
///
/// Inputs and Outputs:
/// Inputs are the end date, the number of days to cover, and the average daily
/// step count. Output is an ordered array of `StepDaySession` values whose hourly
/// samples never overlap.
///
/// Non-Goals:
/// This file does not request permissions, import HealthKit, or render UI.
import Foundation

struct StepHourlySample: Equatable {
    let interval: DateInterval
    let steps: Int
}

struct StepDaySession: Equatable {
    let date: Date
    let samples: [StepHourlySample]

    var totalSteps: Int {
        samples.reduce(0) { $0 + $1.steps }
    }

    var sampleCount: Int {
        samples.count
    }
}

struct StepGenerationRequest: Equatable {
    var endDate: Date
    var days: Int
    var averageStepsPerDay: Int

    func makeSessions(calendar: Calendar = .current) -> [StepDaySession] {
        guard days > 0, averageStepsPerDay > 0 else {
            return []
        }

        let lastDay = calendar.startOfDay(for: endDate)

        var sessions: [StepDaySession] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7

            // Every day fluctuates around the average, and the hourly shape is
            // perturbed per day so two days never look identical.
            let seed = MockVariation.daySeed(for: day, calendar: calendar)
            let dailyDelta = Int((MockVariation.signedNoise(seed) * 2500).rounded())
            let total = max(0, averageStepsPerDay + dailyDelta + (isWeekend ? 1500 : 0))
            guard total > 0 else {
                continue
            }

            let weights = Self.hourlyWeights.enumerated().map { index, weight in
                weight * (1 + MockVariation.signedNoise(seed &* 100 &+ index) * 0.35)
            }
            let perHour = Self.distribute(total: total, weights: weights)
            var samples: [StepHourlySample] = []
            for (index, steps) in perHour.enumerated() where steps > 0 {
                let hour = Self.startHour + index
                let start = calendar.combine(date: day, hour: hour, minute: 0)
                let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                samples.append(StepHourlySample(interval: DateInterval(start: start, end: end), steps: steps))
            }

            if !samples.isEmpty {
                sessions.append(StepDaySession(date: day, samples: samples))
            }
        }

        return sessions.sorted { $0.date < $1.date }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> StepGenerationRequest {
        StepGenerationRequest(
            endDate: calendar.startOfDay(for: now),
            days: 365,
            averageStepsPerDay: 8000
        )
    }

    static func distribute(total: Int, weights: [Double]) -> [Int] {
        guard total > 0, !weights.isEmpty else {
            return Array(repeating: 0, count: weights.count)
        }

        let safeWeights = weights.map { max(0.0001, $0) }
        let weightSum = safeWeights.reduce(0, +)
        let raw = safeWeights.map { (Double(total) * $0) / weightSum }
        var rounded = raw.map { Int($0.rounded(.down)) }

        let remainder = total - rounded.reduce(0, +)
        let priorities = raw.enumerated()
            .sorted { lhs, rhs in
                let lhsFraction = lhs.element - Double(rounded[lhs.offset])
                let rhsFraction = rhs.element - Double(rounded[rhs.offset])
                return lhsFraction > rhsFraction
            }

        for index in 0..<remainder {
            rounded[priorities[index % priorities.count].offset] += 1
        }

        return rounded
    }

    /// Active hours run 08:00–21:59 (14 buckets), shaped to mimic a commute /
    /// lunch / evening activity curve.
    private static let startHour = 8
    private static let hourlyWeights: [Double] = [
        0.04, 0.06, 0.07, 0.06, 0.09, 0.10, 0.07,
        0.06, 0.06, 0.07, 0.09, 0.10, 0.04, 0.02,
    ]
}

enum StepPreset: String, CaseIterable, Identifiable {
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
            return "最近 7 天，日均约 8000 步，按小时分布并在周末略微上调"
        case .lastMonth:
            return "最近 30 天，日均约 8000 步，适合补一个月的步数记录"
        case .lastYear:
            return "最近 365 天，日均约 8000 步，一次性补满整年的步数记录"
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
        to request: inout StepGenerationRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        request.endDate = calendar.startOfDay(for: now)
        request.days = days
        request.averageStepsPerDay = 8000
    }
}

private extension Calendar {
    func combine(date: Date, hour: Int, minute: Int) -> Date {
        var components = dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return self.date(from: components) ?? date
    }
}
