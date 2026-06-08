/// Purpose:
/// Pure date-generation rules for one or more synthetic sleep sessions.
///
/// Responsibilities:
/// Turn a compact batch request into concrete nightly intervals and staged sleep
/// segments so the HealthKit layer can stay focused on persistence.
///
/// Inputs and Outputs:
/// Inputs are the selected sleep date, bedtime time, number of nights, and
/// duration settings. Output is an ordered array of `SleepSession` values whose
/// stage segments are contiguous and internally consistent.
///
/// Non-Goals:
/// This file does not request permissions, write HealthKit samples, or render UI.
import Foundation

struct SleepGenerationRequest: Equatable {
    var sleepDate: Date
    var bedtimeTime: Date
    var nights: Int
    var sleepDurationMinutes: Int
    var sleepLatencyMinutes: Int
    var overnightAwakeMinutes: Int

    func makeSessions(calendar: Calendar = .current) -> [SleepSession] {
        guard nights > 0, sleepDurationMinutes > 0 else {
            return []
        }

        return (0..<nights)
            .map { offset in
                let adjustedDate = calendar.date(byAdding: .day, value: -offset, to: sleepDate) ?? sleepDate
                let baseBedtime = calendar.combine(
                    date: calendar.startOfDay(for: adjustedDate),
                    withTimeFrom: bedtimeTime
                )

                // Vary every night around the requested values so the batch never
                // looks like the same night copied over and over.
                let seed = MockVariation.daySeed(for: baseBedtime, calendar: calendar)
                let bedtimeShift = Int((MockVariation.signedNoise(seed &* 4) * 30).rounded())
                let bedtime = calendar.date(byAdding: .minute, value: bedtimeShift, to: baseBedtime) ?? baseBedtime
                let durationMinutes = max(60, sleepDurationMinutes + Int((MockVariation.signedNoise(seed &* 4 &+ 1) * 45).rounded()))
                let latencyMinutes = max(0, sleepLatencyMinutes + Int((MockVariation.signedNoise(seed &* 4 &+ 2) * 12).rounded()))
                let awakeMinutes = max(0, overnightAwakeMinutes + Int((MockVariation.signedNoise(seed &* 4 &+ 3) * 15).rounded()))

                return SleepSession.make(
                    bedtime: bedtime,
                    sleepDurationMinutes: durationMinutes,
                    sleepLatencyMinutes: latencyMinutes,
                    overnightAwakeMinutes: awakeMinutes,
                    calendar: calendar
                )
            }
            .sorted { $0.bedtime < $1.bedtime }
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> SleepGenerationRequest {
        let referenceBedtime = calendar.mostRecentBedtime(before: now, hour: 23, minute: 0)
        return SleepGenerationRequest(
            sleepDate: calendar.startOfDay(for: referenceBedtime),
            bedtimeTime: referenceBedtime,
            nights: 1,
            sleepDurationMinutes: 8 * 60,
            sleepLatencyMinutes: 15,
            overnightAwakeMinutes: 20
        )
    }
}

enum SleepStage: String, CaseIterable, Hashable, Identifiable {
    case awake
    case core
    case deep
    case rem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake:
            return "Awake"
        case .core:
            return "Core"
        case .deep:
            return "Deep"
        case .rem:
            return "REM"
        }
    }
}

struct SleepStageSegment: Equatable {
    let stage: SleepStage
    let interval: DateInterval

    var minutes: Int {
        Int(interval.duration / 60)
    }
}

struct SleepSession: Equatable {
    let bedtime: Date
    let wakeTime: Date
    let stageSegments: [SleepStageSegment]

    var inBedInterval: DateInterval {
        DateInterval(start: bedtime, end: wakeTime)
    }

    var sampleCount: Int {
        1 + stageSegments.count
    }

    var stageTotals: [SleepStage: Int] {
        stageSegments.reduce(into: [SleepStage: Int]()) { partialResult, segment in
            partialResult[segment.stage, default: 0] += segment.minutes
        }
    }

    func totalMinutes(for stage: SleepStage) -> Int {
        stageTotals[stage, default: 0]
    }
}

enum QuickPreset: String, CaseIterable, Identifiable {
    case lastNight
    case lastWeek
    case lastMonth
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastNight:
            return "昨晚 8 小时"
        case .lastWeek:
            return "最近 7 晚"
        case .lastMonth:
            return "最近 30 晚"
        case .lastYear:
            return "一键 mock 1 年"
        }
    }

    var subtitle: String {
        switch self {
        case .lastNight:
            return "1 晚，8 小时睡眠，15 分钟入睡耗时，20 分钟夜间清醒"
        case .lastWeek:
            return "7 晚，7 小时 30 分钟睡眠，附带完整 awake/core/deep/REM 分期"
        case .lastMonth:
            return "30 晚，7 小时 45 分钟睡眠，适合批量补整月分期数据"
        case .lastYear:
            return "365 晚，7 小时 45 分钟睡眠，一次性补满整年分期数据"
        }
    }

    func apply(
        to request: inout SleepGenerationRequest,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        let referenceBedtime = calendar.mostRecentBedtime(before: now, hour: 23, minute: 0)
        request.sleepDate = calendar.startOfDay(for: referenceBedtime)
        request.bedtimeTime = referenceBedtime

        switch self {
        case .lastNight:
            request.nights = 1
            request.sleepDurationMinutes = 8 * 60
            request.sleepLatencyMinutes = 15
            request.overnightAwakeMinutes = 20
        case .lastWeek:
            request.nights = 7
            request.sleepDurationMinutes = (7 * 60) + 30
            request.sleepLatencyMinutes = 15
            request.overnightAwakeMinutes = 20
        case .lastMonth:
            request.nights = 30
            request.sleepDurationMinutes = (7 * 60) + 45
            request.sleepLatencyMinutes = 10
            request.overnightAwakeMinutes = 25
        case .lastYear:
            request.nights = 365
            request.sleepDurationMinutes = (7 * 60) + 45
            request.sleepLatencyMinutes = 10
            request.overnightAwakeMinutes = 25
        }
    }
}

private extension SleepSession {
    static func make(
        bedtime: Date,
        sleepDurationMinutes: Int,
        sleepLatencyMinutes: Int,
        overnightAwakeMinutes: Int,
        calendar: Calendar
    ) -> SleepSession {
        let stageSegments = makeStageSegments(
            bedtime: bedtime,
            sleepDurationMinutes: sleepDurationMinutes,
            sleepLatencyMinutes: sleepLatencyMinutes,
            overnightAwakeMinutes: overnightAwakeMinutes,
            calendar: calendar
        )

        return SleepSession(
            bedtime: bedtime,
            wakeTime: stageSegments.last?.interval.end ?? bedtime,
            stageSegments: stageSegments
        )
    }

    static func makeStageSegments(
        bedtime: Date,
        sleepDurationMinutes: Int,
        sleepLatencyMinutes: Int,
        overnightAwakeMinutes: Int,
        calendar: Calendar
    ) -> [SleepStageSegment] {
        var cursor = bedtime
        var segments: [SleepStageSegment] = []

        appendSegment(
            stage: .awake,
            minutes: sleepLatencyMinutes,
            to: &segments,
            cursor: &cursor,
            calendar: calendar
        )

        let cycleCount = recommendedCycleCount(for: sleepDurationMinutes)
        let cycleSleepMinutes = distributedMinutes(total: sleepDurationMinutes, weights: cycleWeights(for: cycleCount))
        let deepRatios = deepStageRatios(for: cycleCount)
        let remRatios = remStageRatios(for: cycleCount)
        let awakeBreakMinutes = awakeBreaks(total: overnightAwakeMinutes, cycleCount: cycleCount)

        for cycleIndex in cycleSleepMinutes.indices {
            let cycleMinutes = cycleSleepMinutes[cycleIndex]
            let guaranteedCore = max(10, min(25, cycleMinutes / 2))
            let maximumStageMinutes = max(0, cycleMinutes - guaranteedCore)

            var deepMinutes = Int((Double(cycleMinutes) * deepRatios[cycleIndex]).rounded())
            var remMinutes = Int((Double(cycleMinutes) * remRatios[cycleIndex]).rounded())

            if cycleMinutes >= 35, deepMinutes == 0, deepRatios[cycleIndex] > 0 {
                deepMinutes = 5
            }

            if cycleMinutes >= 35, remMinutes == 0, remRatios[cycleIndex] > 0 {
                remMinutes = 5
            }

            while deepMinutes + remMinutes > maximumStageMinutes {
                if remMinutes >= deepMinutes, remMinutes > 0 {
                    remMinutes -= 1
                } else if deepMinutes > 0 {
                    deepMinutes -= 1
                } else {
                    break
                }
            }

            let coreMinutes = max(0, cycleMinutes - deepMinutes - remMinutes)
            let coreLeadMinutes = coreMinutes <= 20 ? coreMinutes / 2 : Int((Double(coreMinutes) * 0.4).rounded())
            let coreTrailMinutes = coreMinutes - coreLeadMinutes

            appendSegment(
                stage: .core,
                minutes: coreLeadMinutes,
                to: &segments,
                cursor: &cursor,
                calendar: calendar
            )
            appendSegment(
                stage: .deep,
                minutes: deepMinutes,
                to: &segments,
                cursor: &cursor,
                calendar: calendar
            )
            appendSegment(
                stage: .core,
                minutes: coreTrailMinutes,
                to: &segments,
                cursor: &cursor,
                calendar: calendar
            )
            appendSegment(
                stage: .rem,
                minutes: remMinutes,
                to: &segments,
                cursor: &cursor,
                calendar: calendar
            )

            if cycleIndex < awakeBreakMinutes.count {
                appendSegment(
                    stage: .awake,
                    minutes: awakeBreakMinutes[cycleIndex],
                    to: &segments,
                    cursor: &cursor,
                    calendar: calendar
                )
            }
        }

        return segments
    }

    static func appendSegment(
        stage: SleepStage,
        minutes: Int,
        to segments: inout [SleepStageSegment],
        cursor: inout Date,
        calendar: Calendar
    ) {
        guard minutes > 0 else {
            return
        }

        let segmentEnd = calendar.date(byAdding: .minute, value: minutes, to: cursor) ?? cursor
        let interval = DateInterval(start: cursor, end: segmentEnd)

        if let lastSegment = segments.last, lastSegment.stage == stage, lastSegment.interval.end == cursor {
            segments[segments.count - 1] = SleepStageSegment(
                stage: stage,
                interval: DateInterval(start: lastSegment.interval.start, end: segmentEnd)
            )
        } else {
            segments.append(SleepStageSegment(stage: stage, interval: interval))
        }

        cursor = segmentEnd
    }

    static func recommendedCycleCount(for sleepDurationMinutes: Int) -> Int {
        min(4, max(2, sleepDurationMinutes / 120))
    }

    static func cycleWeights(for count: Int) -> [Double] {
        switch count {
        case 2:
            return [0.56, 0.44]
        case 3:
            return [0.38, 0.34, 0.28]
        default:
            return [0.30, 0.27, 0.23, 0.20]
        }
    }

    static func deepStageRatios(for count: Int) -> [Double] {
        switch count {
        case 2:
            return [0.24, 0.08]
        case 3:
            return [0.26, 0.14, 0.04]
        default:
            return [0.28, 0.16, 0.07, 0.0]
        }
    }

    static func remStageRatios(for count: Int) -> [Double] {
        switch count {
        case 2:
            return [0.12, 0.28]
        case 3:
            return [0.10, 0.20, 0.32]
        default:
            return [0.10, 0.17, 0.27, 0.38]
        }
    }

    static func awakeBreaks(total: Int, cycleCount: Int) -> [Int] {
        let maximumGapCount = max(0, cycleCount - 1)
        guard total > 0, maximumGapCount > 0 else {
            return []
        }

        let gapCount: Int
        if total < 10 {
            gapCount = 1
        } else if total < 20 {
            gapCount = min(maximumGapCount, 2)
        } else {
            gapCount = maximumGapCount
        }

        let compactBreaks = distributedMinutes(
            total: total,
            weights: Array(1...gapCount).map { Double($0) }
        )

        var breaks = Array(repeating: 0, count: maximumGapCount)
        let startingIndex = maximumGapCount - compactBreaks.count
        for (offset, value) in compactBreaks.enumerated() {
            breaks[startingIndex + offset] = value
        }

        return breaks
    }

    static func distributedMinutes(total: Int, weights: [Double]) -> [Int] {
        guard total > 0, !weights.isEmpty else {
            return Array(repeating: 0, count: weights.count)
        }

        let safeWeights = weights.map { max(0.0001, $0) }
        let weightSum = safeWeights.reduce(0, +)
        let rawDistribution = safeWeights.map { (Double(total) * $0) / weightSum }
        var roundedMinutes = rawDistribution.map { Int($0.rounded(.down)) }

        let remainder = total - roundedMinutes.reduce(0, +)
        let priorities = rawDistribution.enumerated()
            .sorted { lhs, rhs in
                let lhsFraction = lhs.element - Double(roundedMinutes[lhs.offset])
                let rhsFraction = rhs.element - Double(roundedMinutes[rhs.offset])
                return lhsFraction > rhsFraction
            }

        for index in 0..<remainder {
            roundedMinutes[priorities[index % priorities.count].offset] += 1
        }

        return roundedMinutes
    }
}

private extension Calendar {
    func mostRecentBedtime(before now: Date, hour: Int, minute: Int) -> Date {
        var components = dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let candidate = date(from: components) ?? now
        if candidate <= now {
            return candidate
        }

        return date(byAdding: .day, value: -1, to: candidate) ?? candidate
    }

    func combine(date: Date, withTimeFrom time: Date) -> Date {
        let dayComponents = self.dateComponents([.year, .month, .day], from: date)
        let timeComponents = self.dateComponents([.hour, .minute, .second], from: time)

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
