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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .hrv:
            return "HRV"
        }
    }

    var navigationTitle: String {
        switch self {
        case .sleep:
            return "Sleep Data"
        case .hrv:
            return "HRV Data"
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
}

struct HRVWriteRequest: Equatable {
    var recordDate: Date
    var sampleTime: Date
    var preset: HRVPreset

    var valueMilliseconds: Double {
        preset.valueMilliseconds
    }

    func sampleDate(calendar: Calendar = .current) -> Date {
        calendar.combineHRVDate(
            date: calendar.startOfDay(for: recordDate),
            withTimeFrom: sampleTime
        )
    }

    static func `default`(calendar: Calendar = .current, now: Date = Date()) -> HRVWriteRequest {
        HRVWriteRequest(
            recordDate: calendar.startOfDay(for: now),
            sampleTime: now,
            preset: .tooLow
        )
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
