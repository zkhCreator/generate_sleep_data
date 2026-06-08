/// Purpose:
/// Pure date-generation rules for a batch of synthetic menstrual-flow records.
///
/// Responsibilities:
/// Walk repeating cycles backwards over a date range, emitting one daily flow
/// record per period day with a believable heavy→light taper, marking the first
/// day of each cycle, and letting cycle/period lengths fluctuate a little so the
/// history never looks perfectly periodic.
///
/// Inputs and Outputs:
/// Inputs are the end date, the number of days to cover, the average cycle length
/// and the average period length. Output is an ordered array of
/// `MenstrualDaySample` values whose days never overlap.
///
/// Non-Goals:
/// This file does not request permissions, import HealthKit, or render UI. The
/// mapping from `MenstrualFlowLevel` to HealthKit category values lives in the
/// HealthKit layer.
import Foundation

enum MenstrualFlowLevel: String, CaseIterable, Identifiable {
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "少量"
        case .medium:
            return "中等"
        case .heavy:
            return "大量"
        }
    }
}

struct MenstrualDaySample: Equatable {
    let date: Date
    let flow: MenstrualFlowLevel
    let isCycleStart: Bool
}

struct MenstrualGenerationRequest: Equatable {
    var endDate: Date
    var days: Int
    var cycleLength: Int
    var periodLength: Int

    func makeSamples(calendar: Calendar = .current) -> [MenstrualDaySample] {
        guard days > 0, periodLength > 0, cycleLength > periodLength else {
            return []
        }

        let endDay = calendar.startOfDay(for: endDate)
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return []
        }

        var samples: [MenstrualDaySample] = []
        var cycleStart = firstDay

        while cycleStart <= endDay {
            // Let each cycle drift a little so periods don't land on a perfect grid.
            let seed = MockVariation.daySeed(for: cycleStart, calendar: calendar)
            let thisCycleLength = max(periodLength + 1, cycleLength + Int((MockVariation.signedNoise(seed) * 2).rounded()))
            let thisPeriodLength = max(2, periodLength + Int((MockVariation.signedNoise(seed &* 3 &+ 1) * 1).rounded()))

            for periodDay in 0..<thisPeriodLength {
                guard let day = calendar.date(byAdding: .day, value: periodDay, to: cycleStart) else {
                    continue
                }
                if day > endDay {
                    break
                }
                if day >= firstDay {
                    samples.append(
                        MenstrualDaySample(
                            date: day,
                            flow: Self.flow(forPeriodDay: periodDay, periodLength: thisPeriodLength),
                            isCycleStart: periodDay == 0
                        )
                    )
                }
            }

            guard let nextStart = calendar.date(byAdding: .day, value: thisCycleLength, to: cycleStart) else {
                break
            }
            cycleStart = nextStart
        }

        return samples.sorted { $0.date < $1.date }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> MenstrualGenerationRequest {
        MenstrualGenerationRequest(
            endDate: calendar.startOfDay(for: now),
            days: 365,
            cycleLength: 28,
            periodLength: 5
        )
    }

    /// A typical heavy-in-the-middle taper across the period.
    static func flow(forPeriodDay periodDay: Int, periodLength: Int) -> MenstrualFlowLevel {
        let progress = Double(periodDay) / Double(max(1, periodLength - 1))
        switch progress {
        case ..<0.15:
            return .medium
        case ..<0.5:
            return .heavy
        case ..<0.75:
            return .medium
        default:
            return .light
        }
    }
}

enum MenstrualPreset: String, CaseIterable, Identifiable {
    case lastThreeMonths
    case lastSixMonths
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastThreeMonths:
            return "最近 3 个月"
        case .lastSixMonths:
            return "最近 6 个月"
        case .lastYear:
            return "一键 mock 1 年"
        }
    }

    var subtitle: String {
        switch self {
        case .lastThreeMonths:
            return "最近 90 天，约 3 个周期，28 天周期 / 5 天经期"
        case .lastSixMonths:
            return "最近 180 天，约 6 个周期，适合补半年的经期记录"
        case .lastYear:
            return "最近 365 天，约 13 个周期，一次性补满整年的经期记录"
        }
    }

    var days: Int {
        switch self {
        case .lastThreeMonths:
            return 90
        case .lastSixMonths:
            return 180
        case .lastYear:
            return 365
        }
    }

    func apply(
        to request: inout MenstrualGenerationRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        request.endDate = calendar.startOfDay(for: now)
        request.days = days
    }
}
