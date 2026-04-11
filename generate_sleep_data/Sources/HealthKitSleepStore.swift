/// Purpose:
/// HealthKit adapter that writes synthetic sleep and HRV samples into Apple Health.
///
/// Responsibilities:
/// Request the minimum write authorization needed by the current mode, persist
/// sleep-analysis samples or today's HRV sample, print the outgoing write payload
/// to the console for debugging, and delete previously generated sleep samples
/// inside a requested time range.
///
/// Inputs and Outputs:
/// Input is either a `SleepGenerationRequest` or an `HRVWriteRequest`. Output is
/// a typed write/delete result describing the affected sample count, or an error
/// when HealthKit is unavailable or unauthorized.
///
/// Non-Goals:
/// This file does not own UI state, generation rules, or read back history.
import Foundation
import HealthKit

protocol HealthDataWriting: AnyObject {
    func authorizationStatus(for mode: HealthDataMode) -> HealthAuthorizationState
    func requestAuthorization(for mode: HealthDataMode) async throws -> HealthAuthorizationState
    func writeSleepData(for request: SleepGenerationRequest) async throws -> SleepWriteResult
    func writeHRVData(for request: HRVWriteRequest) async throws -> HRVWriteResult
    func deleteGeneratedSleepData(for request: SleepGenerationRequest) async throws -> SleepDeleteResult
}

enum HealthAuthorizationState: Equatable {
    case unavailable
    case notDetermined
    case sharingDenied
    case sharingAuthorized

    var isAuthorized: Bool {
        self == .sharingAuthorized
    }
}

struct SleepWriteResult: Equatable {
    let batchID: String
    let sessionCount: Int
    let sampleCount: Int
}

struct HRVWriteResult: Equatable {
    let sampleCount: Int
    let valueMilliseconds: Double
    let sampleDate: Date
}

struct SleepDeleteResult: Equatable {
    let deletedSampleCount: Int
}

enum HealthStoreError: LocalizedError {
    case healthDataUnavailable
    case sleepTypeUnavailable
    case hrvTypeUnavailable
    case authorizationRequired
    case emptySleepRequest

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前环境不支持 HealthKit。请在已开启 Health 的 iPhone 真机上运行。"
        case .sleepTypeUnavailable:
            return "当前系统无法创建 sleepAnalysis 类型。"
        case .hrvTypeUnavailable:
            return "当前系统无法创建 HRV 类型。"
        case .authorizationRequired:
            return "没有拿到 Health 写入权限。"
        case .emptySleepRequest:
            return "没有可写入的 sleep data。请检查晚数和睡眠时长。"
        }
    }
}

final class HealthKitStore: HealthDataWriting {
    private static let batchIDKey = "io.tuist.generate-sleep-data.batch-id"
    private static let sampleKindKey = "io.tuist.generate-sleep-data.sample-kind"

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func authorizationStatus(for mode: HealthDataMode) -> HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        guard let sampleType = sampleType(for: mode) else {
            return .unavailable
        }

        switch healthStore.authorizationStatus(for: sampleType) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .sharingDenied
        case .sharingAuthorized:
            return .sharingAuthorized
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization(for mode: HealthDataMode) async throws -> HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        let shareTypes: Set<HKSampleType> = [try requireSampleType(for: mode)]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: nil) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                    return
                }

                continuation.resume(throwing: HealthStoreError.authorizationRequired)
            }
        }

        return authorizationStatus(for: mode)
    }

    func writeSleepData(for request: SleepGenerationRequest) async throws -> SleepWriteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .sleep).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let sleepType = try requireSleepType()
        let sessions = request.makeSessions()
        guard !sessions.isEmpty else {
            throw HealthStoreError.emptySleepRequest
        }

        let batchID = UUID().uuidString
        let samples = makeSleepSamples(for: sessions, sleepType: sleepType, batchID: batchID)
        logSleepWrite(batchID: batchID, request: request, sessions: sessions, sampleCount: samples.count)
        try await save(samples)
        print("[HealthWrite][Sleep] save succeeded. batchID=\(batchID) sampleCount=\(samples.count)")

        return SleepWriteResult(
            batchID: batchID,
            sessionCount: sessions.count,
            sampleCount: samples.count
        )
    }

    func writeHRVData(for request: HRVWriteRequest) async throws -> HRVWriteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .hrv).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let hrvType = try requireHRVType()
        let sampleDate = request.sampleDate()
        let quantity = HKQuantity(
            unit: HKUnit.secondUnit(with: .milli),
            doubleValue: request.valueMilliseconds
        )
        let sample = HKQuantitySample(
            type: hrvType,
            quantity: quantity,
            start: sampleDate,
            end: sampleDate,
            metadata: [
                HKMetadataKeyWasUserEntered: true,
                Self.sampleKindKey: "hrv",
            ]
        )
        logHRVWrite(request: request, sampleDate: sampleDate)
        try await save([sample])
        print("[HealthWrite][HRV] save succeeded. sampleCount=1")

        return HRVWriteResult(
            sampleCount: 1,
            valueMilliseconds: request.valueMilliseconds,
            sampleDate: sampleDate
        )
    }

    func deleteGeneratedSleepData(for request: SleepGenerationRequest) async throws -> SleepDeleteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .sleep).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let sleepType = try requireSleepType()
        let sessions = request.makeSessions()
        guard let firstSession = sessions.first, let lastSession = sessions.last else {
            throw HealthStoreError.emptySleepRequest
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: firstSession.bedtime,
            end: lastSession.wakeTime,
            options: .strictStartDate
        )
        let metadataPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.batchIDKey)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, metadataPredicate])
        let deletedSampleCount = try await deleteObjects(of: sleepType, predicate: predicate)

        return SleepDeleteResult(deletedSampleCount: deletedSampleCount)
    }

    private func sampleType(for mode: HealthDataMode) -> HKSampleType? {
        switch mode {
        case .sleep:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .hrv:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        }
    }

    private func requireSampleType(for mode: HealthDataMode) throws -> HKSampleType {
        guard let sampleType = sampleType(for: mode) else {
            switch mode {
            case .sleep:
                throw HealthStoreError.sleepTypeUnavailable
            case .hrv:
                throw HealthStoreError.hrvTypeUnavailable
            }
        }

        return sampleType
    }

    private func requireSleepType() throws -> HKCategoryType {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthStoreError.sleepTypeUnavailable
        }

        return sleepType
    }

    private func requireHRVType() throws -> HKQuantityType {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthStoreError.hrvTypeUnavailable
        }

        return hrvType
    }

    private func makeSleepSamples(
        for sessions: [SleepSession],
        sleepType: HKCategoryType,
        batchID: String
    ) -> [HKCategorySample] {
        sessions.enumerated().flatMap { index, session in
            let baseMetadata: [String: Any] = [
                HKMetadataKeyWasUserEntered: true,
                Self.batchIDKey: batchID,
                "io.tuist.generate-sleep-data.session-index": index,
            ]

            let inBed = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: session.inBedInterval.start,
                end: session.inBedInterval.end,
                metadata: baseMetadata.merging([Self.sampleKindKey: "inBed"]) { _, new in new }
            )

            let stageSamples = session.stageSegments.enumerated().map { stageIndex, segment in
                HKCategorySample(
                    type: sleepType,
                    value: healthKitValue(for: segment.stage).rawValue,
                    start: segment.interval.start,
                    end: segment.interval.end,
                    metadata: baseMetadata.merging(
                        [
                            Self.sampleKindKey: segment.stage.rawValue,
                            "io.tuist.generate-sleep-data.stage-index": stageIndex,
                        ]
                    ) { _, new in new }
                )
            }

            return [inBed] + stageSamples
        }
    }

    private func healthKitValue(for stage: SleepStage) -> HKCategoryValueSleepAnalysis {
        switch stage {
        case .awake:
            return .awake
        case .core:
            return .asleepCore
        case .deep:
            return .asleepDeep
        case .rem:
            return .asleepREM
        }
    }

    private func save(_ samples: [HKSample]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                    return
                }

                continuation.resume(throwing: HealthStoreError.authorizationRequired)
            }
        }
    }

    private func logSleepWrite(
        batchID: String,
        request: SleepGenerationRequest,
        sessions: [SleepSession],
        sampleCount: Int
    ) {
        print(
            """
            [HealthWrite][Sleep] preparing save.
            batchID=\(batchID)
            sleepDate=\(Self.consoleDateFormatter.string(from: request.sleepDate))
            bedtimeTime=\(Self.consoleTimeFormatter.string(from: request.bedtimeTime))
            nights=\(request.nights)
            sleepDurationMinutes=\(request.sleepDurationMinutes)
            sleepLatencyMinutes=\(request.sleepLatencyMinutes)
            overnightAwakeMinutes=\(request.overnightAwakeMinutes)
            sessionCount=\(sessions.count)
            sampleCount=\(sampleCount)
            """
        )

        for (sessionIndex, session) in sessions.enumerated() {
            print(
                """
                [HealthWrite][Sleep][Session \(sessionIndex + 1)]
                inBedStart=\(Self.consoleDateTimeFormatter.string(from: session.inBedInterval.start))
                inBedEnd=\(Self.consoleDateTimeFormatter.string(from: session.inBedInterval.end))
                totalMinutes=\(Int(session.inBedInterval.duration / 60))
                """
            )

            for (stageIndex, segment) in session.stageSegments.enumerated() {
                print(
                    """
                    [HealthWrite][Sleep][Session \(sessionIndex + 1)][Stage \(stageIndex + 1)]
                    stage=\(segment.stage.rawValue)
                    start=\(Self.consoleDateTimeFormatter.string(from: segment.interval.start))
                    end=\(Self.consoleDateTimeFormatter.string(from: segment.interval.end))
                    minutes=\(segment.minutes)
                    """
                )
            }
        }
    }

    private func logHRVWrite(request: HRVWriteRequest, sampleDate: Date) {
        print(
            """
            [HealthWrite][HRV] preparing save.
            preset=\(request.preset.rawValue)
            state=\(request.preset.title)
            recordDate=\(Self.consoleDateFormatter.string(from: request.recordDate))
            sampleTime=\(Self.consoleTimeFormatter.string(from: request.sampleTime))
            sampleDate=\(Self.consoleDateTimeFormatter.string(from: sampleDate))
            valueMilliseconds=\(request.valueMilliseconds)
            """
        )
    }

    private func deleteObjects(of type: HKObjectType, predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: type, predicate: predicate) { success, deletedObjectCount, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard success else {
                    continuation.resume(throwing: HealthStoreError.authorizationRequired)
                    return
                }

                continuation.resume(returning: deletedObjectCount)
            }
        }
    }

    private static let consoleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let consoleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let consoleDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
