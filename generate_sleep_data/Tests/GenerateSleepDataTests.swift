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

        XCTAssertEqual(firstSession.bedtime, makeDate(year: 2026, month: 4, day: 9, hour: 23, minute: 0))
        XCTAssertEqual(firstSession.wakeTime, makeDate(year: 2026, month: 4, day: 10, hour: 7, minute: 35))
        XCTAssertEqual(lastSession.bedtime, makeDate(year: 2026, month: 4, day: 11, hour: 23, minute: 0))
        XCTAssertEqual(lastSession.wakeTime, makeDate(year: 2026, month: 4, day: 12, hour: 7, minute: 35))

        XCTAssertEqual(firstSession.totalMinutes(for: .awake), 35)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .core), 0)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .deep), 0)
        XCTAssertGreaterThan(firstSession.totalMinutes(for: .rem), 0)
        XCTAssertEqual(Set(firstSession.stageSegments.map(\.stage)), Set(SleepStage.allCases))
        XCTAssertEqual(
            firstSession.stageSegments.reduce(0) { $0 + $1.minutes },
            8 * 60 + 15 + 20
        )
        XCTAssertEqual(firstSession.sampleCount, firstSession.stageSegments.count + 1)

        for (previous, current) in zip(firstSession.stageSegments, firstSession.stageSegments.dropFirst()) {
            XCTAssertEqual(previous.interval.end, current.interval.start)
        }
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

        XCTAssertEqual(session.bedtime, makeDate(year: 2026, month: 4, day: 15, hour: 22, minute: 30))
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
