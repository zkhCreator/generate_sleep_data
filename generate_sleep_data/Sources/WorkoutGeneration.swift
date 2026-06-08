/// Purpose:
/// Pure date-generation rules for a batch of synthetic workout sessions.
///
/// Responsibilities:
/// Turn a compact batch request (how many days back, how many workouts per week)
/// into concrete dated workout sessions with duration, energy, and optional
/// distance, so the HealthKit layer can stay focused on persistence.
///
/// Inputs and Outputs:
/// Inputs are the end date, the number of days to cover, and the weekly workout
/// frequency. Output is an ordered array of `WorkoutSession` values whose
/// intervals never overlap on the same day.
///
/// Non-Goals:
/// This file does not request permissions, import HealthKit, or render UI. The
/// mapping from `WorkoutKind` to concrete HealthKit activity/quantity types lives
/// in the HealthKit layer.
import Foundation

enum WorkoutDistanceKind: Equatable {
    case walkingRunning
    case cycling
    case swimming
}

enum WorkoutKind: String, CaseIterable, Identifiable {
    case running
    case walking
    case cycling
    case strength
    case hiking
    case yoga
    case swimming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running:
            return "跑步"
        case .walking:
            return "步行"
        case .cycling:
            return "骑行"
        case .strength:
            return "力量训练"
        case .hiking:
            return "徒步"
        case .yoga:
            return "瑜伽"
        case .swimming:
            return "游泳"
        }
    }

    /// Typical duration for this workout, before any per-day jitter.
    var baseDurationMinutes: Int {
        switch self {
        case .running:
            return 35
        case .walking:
            return 45
        case .cycling:
            return 50
        case .strength:
            return 45
        case .hiking:
            return 90
        case .yoga:
            return 40
        case .swimming:
            return 35
        }
    }

    /// Active energy burned per minute, used to derive total kilocalories.
    var kilocaloriesPerMinute: Double {
        switch self {
        case .running:
            return 11
        case .walking:
            return 5
        case .cycling:
            return 8
        case .strength:
            return 7
        case .hiking:
            return 7
        case .yoga:
            return 4
        case .swimming:
            return 9
        }
    }

    /// Meters covered per minute, used to derive total distance.
    var metersPerMinute: Double {
        switch self {
        case .running:
            return 160
        case .walking:
            return 90
        case .cycling:
            return 300
        case .strength:
            return 0
        case .hiking:
            return 70
        case .yoga:
            return 0
        case .swimming:
            return 30
        }
    }

    var distanceKind: WorkoutDistanceKind? {
        switch self {
        case .running, .walking, .hiking:
            return .walkingRunning
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .strength, .yoga:
            return nil
        }
    }

    /// Hour of day the session typically starts.
    var startHour: Int {
        switch self {
        case .running:
            return 7
        case .walking:
            return 18
        case .cycling:
            return 17
        case .strength:
            return 19
        case .hiking:
            return 9
        case .yoga:
            return 8
        case .swimming:
            return 18
        }
    }
}

struct WorkoutSession: Equatable {
    let kind: WorkoutKind
    let start: Date
    let end: Date
    let kilocalories: Double
    let distanceMeters: Double?

    var interval: DateInterval {
        DateInterval(start: start, end: end)
    }

    var durationMinutes: Int {
        Int(interval.duration / 60)
    }
}

struct WorkoutGenerationRequest: Equatable {
    var endDate: Date
    var days: Int
    var workoutsPerWeek: Int

    func makeSessions(calendar: Calendar = .current) -> [WorkoutSession] {
        guard days > 0 else {
            return []
        }

        let perWeek = min(7, max(0, workoutsPerWeek))
        guard perWeek > 0 else {
            return []
        }

        let activeWeekdays = Self.activeWeekdays(perWeek: perWeek)
        let lastDay = calendar.startOfDay(for: endDate)

        var sessions: [WorkoutSession] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: day)
            guard activeWeekdays.contains(weekday) else {
                continue
            }

            let kind = WorkoutKind.allCases[offset % WorkoutKind.allCases.count]

            // Vary each session's length and start minute per day so repeated
            // workouts of the same kind differ from one another.
            let seed = MockVariation.daySeed(for: day, calendar: calendar)
            let durationJitter = Int((MockVariation.signedNoise(seed &* 7 &+ 1) * 12).rounded())
            let durationMinutes = max(10, kind.baseDurationMinutes + durationJitter)
            let startMinute = Int(MockVariation.unitNoise(seed &* 7 &+ 2) * 60)

            let start = calendar.combine(date: day, hour: kind.startHour, minute: startMinute)
            let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start

            let kilocalories = (Double(durationMinutes) * kind.kilocaloriesPerMinute).rounded()
            let distanceMeters = kind.distanceKind == nil
                ? nil
                : (Double(durationMinutes) * kind.metersPerMinute).rounded()

            sessions.append(
                WorkoutSession(
                    kind: kind,
                    start: start,
                    end: end,
                    kilocalories: kilocalories,
                    distanceMeters: distanceMeters
                )
            )
        }

        return sessions.sorted { $0.start < $1.start }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> WorkoutGenerationRequest {
        WorkoutGenerationRequest(
            endDate: calendar.startOfDay(for: now),
            days: 365,
            workoutsPerWeek: 4
        )
    }

    /// Spreads the weekly workouts across the week deterministically. Calendar
    /// weekdays are 1 (Sunday) through 7 (Saturday).
    static func activeWeekdays(perWeek: Int) -> Set<Int> {
        let priority = [2, 4, 6, 1, 3, 7, 5]
        return Set(priority.prefix(perWeek))
    }

}

enum WorkoutPreset: String, CaseIterable, Identifiable {
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
            return "最近 7 天，每周 4 次锻炼，自动轮换跑步 / 骑行 / 力量等类型"
        case .lastMonth:
            return "最近 30 天，每周 4 次锻炼，适合补一个月的运动记录"
        case .lastYear:
            return "最近 365 天，每周 4 次锻炼，一次性补满整年的运动记录"
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
        to request: inout WorkoutGenerationRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        request.endDate = calendar.startOfDay(for: now)
        request.days = days
        request.workoutsPerWeek = 4
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
