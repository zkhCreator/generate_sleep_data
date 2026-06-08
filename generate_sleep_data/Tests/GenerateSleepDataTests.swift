/// Purpose:
/// Unit tests for the pure generation rules behind sleep and HRV writes.
///
/// Responsibilities:
/// Verify the nightly sleep expansion logic, today's HRV timestamp composition,
/// and the default heuristics without talking to HealthKit or SwiftUI.
///
/// Non-Goals:
/// These tests do not validate entitlements, permissions, or real Health writes.
import Foundation
import XCTest
@testable import generate_sleep_data

final class GenerateSleepDataTests: XCTestCase {
    func test_makeSessions_buildsOrderedNightlySessionsWithStages() throws {
        let request = SleepGenerationRequest(
            sleepDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            bedtimeTime: makeDate(year: 2020, month: 1, day: 1, hour: 23, minute: 0),
            nights: 3,
            sleepDurationMinutes: 8 * 60,
            sleepLatencyMinutes: 15,
            overnightAwakeMinutes: 20
        )

        let sessions = request.makeSessions(calendar: calendar)

        XCTAssertEqual(sessions.count, 3)
        let firstSession = try XCTUnwrap(sessions.first)
        let lastSession = try XCTUnwrap(sessions.last)

        // Bedtimes fluctuate up to ±30 minutes around the requested 23:00 anchor.
        XCTAssertEqual(
            firstSession.bedtime.timeIntervalSince(makeDate(year: 2026, month: 4, day: 9, hour: 23, minute: 0)),
            0,
            accuracy: 30 * 60
        )
        XCTAssertEqual(
            lastSession.bedtime.timeIntervalSince(makeDate(year: 2026, month: 4, day: 11, hour: 23, minute: 0)),
            0,
            accuracy: 30 * 60
        )
        XCTAssertLessThan(firstSession.bedtime, lastSession.bedtime)
        XCTAssertGreaterThan(firstSession.wakeTime, firstSession.bedtime)

        XCTAssertGreaterThan(firstSession.totalMinutes(for: .awake), 0)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .core), 0)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .deep), 0)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .rem), 0)
        XCTAssertEqual(Set(firstSession.stageSegments.map(\.stage)), Set(SleepStage.allCases))
        // The staged segments always tile the whole in-bed interval exactly.
        XCTAssertEqual(
            firstSession.stageSegments.reduce(0) { $0 + $1.minutes },
            Int(firstSession.inBedInterval.duration / 60)
        )
        XCTAssertEqual(firstSession.sampleCount, firstSession.stageSegments.count + 1)

        for (previous, current) in zip(firstSession.stageSegments, firstSession.stageSegments.dropFirst()) {
            XCTAssertEqual(previous.interval.end, current.interval.start)
        }
    }

    func test_makeSessions_variesNightToNight() {
        let request = SleepGenerationRequest(
            sleepDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            bedtimeTime: makeDate(year: 2020, month: 1, day: 1, hour: 23, minute: 0),
            nights: 30,
            sleepDurationMinutes: 8 * 60,
            sleepLatencyMinutes: 15,
            overnightAwakeMinutes: 20
        )

        let durations = Set(request.makeSessions(calendar: calendar).map { Int($0.inBedInterval.duration / 60) })
        // Nights should not all be identical copies.
        XCTAssertGreaterThan(durations.count, 1)
    }

    func test_defaultRequest_usesMostRecentElevenPmBeforeNow() {
        let morningNow = makeDate(year: 2026, month: 4, day: 11, hour: 9, minute: 30)
        let lateNightNow = makeDate(year: 2026, month: 4, day: 11, hour: 23, minute: 30)

        let morningRequest = SleepGenerationRequest.default(calendar: calendar, now: morningNow)
        let lateNightRequest = SleepGenerationRequest.default(calendar: calendar, now: lateNightNow)

        XCTAssertEqual(morningRequest.sleepDate, makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0))
        XCTAssertEqual(lateNightRequest.sleepDate, makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0))
        XCTAssertEqual(hour(from: morningRequest.bedtimeTime), 23)
        XCTAssertEqual(minute(from: morningRequest.bedtimeTime), 0)
        XCTAssertEqual(hour(from: lateNightRequest.bedtimeTime), 23)
        XCTAssertEqual(minute(from: lateNightRequest.bedtimeTime), 0)
    }

    func test_selectedSleepDate_isCombinedWithChosenBedtimeTime() throws {
        let request = SleepGenerationRequest(
            sleepDate: makeDate(year: 2026, month: 4, day: 15, hour: 0, minute: 0),
            bedtimeTime: makeDate(year: 1999, month: 1, day: 1, hour: 22, minute: 30),
            nights: 1,
            sleepDurationMinutes: 6 * 60,
            sleepLatencyMinutes: 10,
            overnightAwakeMinutes: 15
        )

        let session = try XCTUnwrap(request.makeSessions(calendar: calendar).first)

        // Combined with the chosen 22:30 time, then varied by at most ±30 minutes.
        XCTAssertEqual(
            session.bedtime.timeIntervalSince(makeDate(year: 2026, month: 4, day: 15, hour: 22, minute: 30)),
            0,
            accuracy: 30 * 60
        )
    }

    func test_defaultHRVRequest_anchorsToToday() {
        let now = makeDate(year: 2026, month: 4, day: 11, hour: 9, minute: 30)

        let request = HRVWriteRequest.default(calendar: calendar, now: now)

        XCTAssertEqual(request.recordDate, makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0))
        XCTAssertEqual(hour(from: request.sampleTime), 9)
        XCTAssertEqual(minute(from: request.sampleTime), 30)
        XCTAssertEqual(request.preset, .tooLow)
        XCTAssertEqual(request.valueMilliseconds, 12)
    }

    func test_hrvRequest_buildsTodaySampleDateFromSelectedTime() {
        let request = HRVWriteRequest(
            recordDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            sampleTime: makeDate(year: 1999, month: 1, day: 1, hour: 8, minute: 45),
            preset: .tooHigh
        )

        XCTAssertEqual(
            request.sampleDate(calendar: calendar),
            makeDate(year: 2026, month: 4, day: 11, hour: 8, minute: 45)
        )
        XCTAssertEqual(request.valueMilliseconds, 82)
    }

    func test_defaultWorkoutRequest_coversOneYearFourTimesPerWeek() {
        let now = makeDate(year: 2026, month: 4, day: 11, hour: 9, minute: 30)

        let request = WorkoutGenerationRequest.default(calendar: calendar, now: now)

        XCTAssertEqual(request.endDate, makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0))
        XCTAssertEqual(request.days, 365)
        XCTAssertEqual(request.workoutsPerWeek, 4)

        let sessions = request.makeSessions(calendar: calendar)
        // 365 days at 4 active weekdays per week ≈ 208 sessions; allow slack for edges.
        XCTAssertGreaterThan(sessions.count, 190)
        XCTAssertLessThan(sessions.count, 220)
    }

    func test_workoutMakeSessions_isOrderedAndRespectsActiveWeekdays() throws {
        let request = WorkoutGenerationRequest(
            endDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            days: 28,
            workoutsPerWeek: 4
        )

        let sessions = request.makeSessions(calendar: calendar)
        let activeWeekdays = WorkoutGenerationRequest.activeWeekdays(perWeek: 4)

        XCTAssertFalse(sessions.isEmpty)
        // 4 sessions per week over 4 weeks.
        XCTAssertEqual(sessions.count, 16)

        let windowStart = makeDate(year: 2026, month: 3, day: 15, hour: 0, minute: 0)
        for (previous, current) in zip(sessions, sessions.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.start, current.start)
        }

        for session in sessions {
            XCTAssertGreaterThanOrEqual(session.start, windowStart)
            XCTAssertTrue(activeWeekdays.contains(calendar.component(.weekday, from: session.start)))
            XCTAssertGreaterThanOrEqual(session.durationMinutes, 10)
            XCTAssertGreaterThan(session.kilocalories, 0)
            if session.kind.distanceKind == nil {
                XCTAssertNil(session.distanceMeters)
            } else {
                XCTAssertNotNil(session.distanceMeters)
            }
        }
    }

    func test_workoutMakeSessions_zeroFrequencyProducesNothing() {
        let request = WorkoutGenerationRequest(
            endDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            days: 30,
            workoutsPerWeek: 0
        )

        XCTAssertTrue(request.makeSessions(calendar: calendar).isEmpty)
    }

    func test_hrvMakeSamples_buildsOneOrderedSamplePerDayWithVariation() throws {
        let request = HRVWriteRequest(
            recordDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            sampleTime: makeDate(year: 1999, month: 1, day: 1, hour: 8, minute: 45),
            preset: .tooHigh,
            days: 30
        )

        let samples = request.makeSamples(calendar: calendar)

        XCTAssertEqual(samples.count, 30)
        let last = try XCTUnwrap(samples.last)
        XCTAssertEqual(last.date, makeDate(year: 2026, month: 4, day: 11, hour: 8, minute: 45))

        for (previous, current) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThan(previous.date, current.date)
        }

        // Every reading stays within the level's variation band around the baseline.
        for sample in samples {
            XCTAssertEqual(sample.valueMilliseconds, 82, accuracy: HRVPreset.tooHigh.variationMilliseconds)
        }

        // And the readings actually fluctuate rather than repeating one value.
        XCTAssertGreaterThan(Set(samples.map(\.valueMilliseconds)).count, 1)
    }

    func test_hrvMakeSamples_singleDayMatchesTodaySampleDate() throws {
        let request = HRVWriteRequest(
            recordDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            sampleTime: makeDate(year: 1999, month: 1, day: 1, hour: 8, minute: 45),
            preset: .tooLow
        )

        let samples = request.makeSamples(calendar: calendar)

        XCTAssertEqual(samples.count, 1)
        let only = try XCTUnwrap(samples.first)
        XCTAssertEqual(only.date, request.sampleDate(calendar: calendar))
    }

    func test_defaultStepRequest_coversOneYearAtEightThousandSteps() {
        let now = makeDate(year: 2026, month: 4, day: 11, hour: 9, minute: 30)

        let request = StepGenerationRequest.default(calendar: calendar, now: now)

        XCTAssertEqual(request.endDate, makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0))
        XCTAssertEqual(request.days, 365)
        XCTAssertEqual(request.averageStepsPerDay, 8000)

        let sessions = request.makeSessions(calendar: calendar)
        XCTAssertEqual(sessions.count, 365)
    }

    func test_stepMakeSessions_dailyTotalMatchesAverageWithWeekendBumpAndHourlySplit() throws {
        let request = StepGenerationRequest(
            endDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            days: 1,
            averageStepsPerDay: 8000
        )

        let session = try XCTUnwrap(request.makeSessions(calendar: calendar).first)

        // 2026-04-11 is a Saturday: base 8000 + 1500 weekend bump + daily noise (±2500).
        XCTAssertGreaterThanOrEqual(session.totalSteps, 8000 + 1500 - 2500)
        XCTAssertLessThanOrEqual(session.totalSteps, 8000 + 1500 + 2500)
        XCTAssertEqual(session.date, makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0))

        // Hourly samples are contiguous and non-overlapping within waking hours.
        for (previous, current) in zip(session.samples, session.samples.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.interval.end, current.interval.start)
            XCTAssertGreaterThan(current.steps, 0)
        }

        let firstStart = try XCTUnwrap(session.samples.first?.interval.start)
        XCTAssertEqual(firstStart, makeDate(year: 2026, month: 4, day: 11, hour: 8, minute: 0))
    }

    func test_stepMakeSessions_zeroAverageProducesNothing() {
        let request = StepGenerationRequest(
            endDate: makeDate(year: 2026, month: 4, day: 11, hour: 0, minute: 0),
            days: 30,
            averageStepsPerDay: 0
        )

        XCTAssertTrue(request.makeSessions(calendar: calendar).isEmpty)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }

    private func hour(from date: Date) -> Int {
        calendar.dateComponents([.hour], from: date).hour ?? 0
    }

    private func minute(from date: Date) -> Int {
        calendar.dateComponents([.minute], from: date).minute ?? 0
    }
}
