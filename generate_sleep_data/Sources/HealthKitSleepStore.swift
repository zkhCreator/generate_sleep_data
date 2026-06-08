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
    func writeWorkoutData(for request: WorkoutGenerationRequest) async throws -> WorkoutWriteResult
    func writeStepData(for request: StepGenerationRequest) async throws -> StepWriteResult
    func deleteGeneratedSleepData(for request: SleepGenerationRequest) async throws -> SleepDeleteResult
    func deleteGeneratedHRVData(for request: HRVWriteRequest) async throws -> HRVDeleteResult
    func deleteGeneratedWorkoutData(for request: WorkoutGenerationRequest) async throws -> WorkoutDeleteResult
    func deleteGeneratedStepData(for request: StepGenerationRequest) async throws -> StepDeleteResult
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
    let batchID: String
    let sampleCount: Int
    let baselineMilliseconds: Double
    let firstDate: Date
    let lastDate: Date
}

struct HRVDeleteResult: Equatable {
    let deletedSampleCount: Int
}

struct SleepDeleteResult: Equatable {
    let deletedSampleCount: Int
}

struct WorkoutWriteResult: Equatable {
    let batchID: String
    let workoutCount: Int
    let totalKilocalories: Double
    let firstStart: Date
    let lastEnd: Date
}

struct WorkoutDeleteResult: Equatable {
    let deletedWorkoutCount: Int
}

struct StepWriteResult: Equatable {
    let batchID: String
    let dayCount: Int
    let sampleCount: Int
    let totalSteps: Int
    let firstStart: Date
    let lastEnd: Date
}

struct StepDeleteResult: Equatable {
    let deletedSampleCount: Int
}

enum HealthStoreError: LocalizedError {
    case healthDataUnavailable
    case sleepTypeUnavailable
    case hrvTypeUnavailable
    case workoutTypeUnavailable
    case stepTypeUnavailable
    case authorizationRequired
    case emptySleepRequest
    case emptyHRVRequest
    case emptyWorkoutRequest
    case emptyStepRequest

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前环境不支持 HealthKit。请在已开启 Health 的 iPhone 真机上运行。"
        case .sleepTypeUnavailable:
            return "当前系统无法创建 sleepAnalysis 类型。"
        case .hrvTypeUnavailable:
            return "当前系统无法创建 HRV 类型。"
        case .workoutTypeUnavailable:
            return "当前系统无法创建 workout 类型。"
        case .stepTypeUnavailable:
            return "当前系统无法创建 stepCount 类型。"
        case .authorizationRequired:
            return "没有拿到 Health 写入权限。"
        case .emptySleepRequest:
            return "没有可写入的 sleep data。请检查晚数和睡眠时长。"
        case .emptyHRVRequest:
            return "没有可写入的 HRV 数据。请检查天数设置。"
        case .emptyWorkoutRequest:
            return "没有可写入的锻炼数据。请检查天数和每周次数。"
        case .emptyStepRequest:
            return "没有可写入的步数数据。请检查天数和日均步数。"
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

        let shareTypes = try shareTypes(for: mode)

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
        for chunk in stride(from: 0, to: samples.count, by: 1000) {
            let upperBound = min(chunk + 1000, samples.count)
            try await save(Array(samples[chunk..<upperBound]))
        }
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
        let daySamples = request.makeSamples()
        guard let firstSample = daySamples.first, let lastSample = daySamples.last else {
            throw HealthStoreError.emptyHRVRequest
        }

        let batchID = UUID().uuidString
        let unit = HKUnit.secondUnit(with: .milli)
        let samples = daySamples.map { daySample in
            HKQuantitySample(
                type: hrvType,
                quantity: HKQuantity(unit: unit, doubleValue: daySample.valueMilliseconds),
                start: daySample.date,
                end: daySample.date,
                metadata: [
                    HKMetadataKeyWasUserEntered: true,
                    Self.batchIDKey: batchID,
                    Self.sampleKindKey: "hrv",
                ]
            )
        }
        logHRVWrite(batchID: batchID, request: request, sampleCount: samples.count)

        for chunk in stride(from: 0, to: samples.count, by: 1000) {
            let upperBound = min(chunk + 1000, samples.count)
            try await save(Array(samples[chunk..<upperBound]))
        }
        print("[HealthWrite][HRV] save succeeded. batchID=\(batchID) sampleCount=\(samples.count)")

        return HRVWriteResult(
            batchID: batchID,
            sampleCount: samples.count,
            baselineMilliseconds: request.valueMilliseconds,
            firstDate: firstSample.date,
            lastDate: lastSample.date
        )
    }

    func writeWorkoutData(for request: WorkoutGenerationRequest) async throws -> WorkoutWriteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .workout).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let sessions = request.makeSessions()
        guard let firstSession = sessions.first, let lastSession = sessions.last else {
            throw HealthStoreError.emptyWorkoutRequest
        }

        let batchID = UUID().uuidString
        logWorkoutWrite(batchID: batchID, request: request, sessions: sessions)

        for (index, session) in sessions.enumerated() {
            try await saveWorkout(session: session, batchID: batchID, index: index)
        }

        print("[HealthWrite][Workout] save succeeded. batchID=\(batchID) workoutCount=\(sessions.count)")

        return WorkoutWriteResult(
            batchID: batchID,
            workoutCount: sessions.count,
            totalKilocalories: sessions.reduce(0) { $0 + $1.kilocalories },
            firstStart: firstSession.start,
            lastEnd: lastSession.end
        )
    }

    func writeStepData(for request: StepGenerationRequest) async throws -> StepWriteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .steps).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let stepType = try requireStepType()
        let sessions = request.makeSessions()
        guard let firstSession = sessions.first, let lastSession = sessions.last,
              let firstStart = firstSession.samples.first?.interval.start,
              let lastEnd = lastSession.samples.last?.interval.end else {
            throw HealthStoreError.emptyStepRequest
        }

        let batchID = UUID().uuidString
        let samples = makeStepSamples(for: sessions, stepType: stepType, batchID: batchID)
        logStepWrite(batchID: batchID, request: request, sessions: sessions, sampleCount: samples.count)

        // Chunk the save so a full year (~5000 samples) stays within a sane batch size.
        for chunk in stride(from: 0, to: samples.count, by: 1000) {
            let upperBound = min(chunk + 1000, samples.count)
            try await save(Array(samples[chunk..<upperBound]))
        }
        print("[HealthWrite][Steps] save succeeded. batchID=\(batchID) sampleCount=\(samples.count)")

        return StepWriteResult(
            batchID: batchID,
            dayCount: sessions.count,
            sampleCount: samples.count,
            totalSteps: sessions.reduce(0) { $0 + $1.totalSteps },
            firstStart: firstStart,
            lastEnd: lastEnd
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

    func deleteGeneratedHRVData(for request: HRVWriteRequest) async throws -> HRVDeleteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .hrv).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let hrvType = try requireHRVType()
        let daySamples = request.makeSamples()
        guard let firstSample = daySamples.first, let lastSample = daySamples.last else {
            throw HealthStoreError.emptyHRVRequest
        }

        // HRV samples are instantaneous, so nudge the end out by a minute to make
        // sure the final day's reading is inside the range.
        let datePredicate = HKQuery.predicateForSamples(
            withStart: firstSample.date,
            end: lastSample.date.addingTimeInterval(60),
            options: .strictStartDate
        )
        let metadataPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.batchIDKey)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, metadataPredicate])
        let deletedSampleCount = try await deleteObjects(of: hrvType, predicate: predicate)

        return HRVDeleteResult(deletedSampleCount: deletedSampleCount)
    }

    func deleteGeneratedWorkoutData(for request: WorkoutGenerationRequest) async throws -> WorkoutDeleteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .workout).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let sessions = request.makeSessions()
        guard let firstSession = sessions.first, let lastSession = sessions.last else {
            throw HealthStoreError.emptyWorkoutRequest
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: firstSession.start,
            end: lastSession.end,
            options: .strictStartDate
        )
        let metadataPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.batchIDKey)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, metadataPredicate])
        let deletedWorkoutCount = try await deleteObjects(of: HKObjectType.workoutType(), predicate: predicate)

        return WorkoutDeleteResult(deletedWorkoutCount: deletedWorkoutCount)
    }

    func deleteGeneratedStepData(for request: StepGenerationRequest) async throws -> StepDeleteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthStoreError.healthDataUnavailable
        }

        guard authorizationStatus(for: .steps).isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }

        let stepType = try requireStepType()
        let sessions = request.makeSessions()
        guard let firstStart = sessions.first?.samples.first?.interval.start,
              let lastEnd = sessions.last?.samples.last?.interval.end else {
            throw HealthStoreError.emptyStepRequest
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: firstStart,
            end: lastEnd,
            options: .strictStartDate
        )
        let metadataPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.batchIDKey)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, metadataPredicate])
        let deletedSampleCount = try await deleteObjects(of: stepType, predicate: predicate)

        return StepDeleteResult(deletedSampleCount: deletedSampleCount)
    }

    private func saveWorkout(session: WorkoutSession, batchID: String, index: Int) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: session.kind)

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )

        try await builder.beginCollection(at: session.start)

        try await builder.addMetadata([
            HKMetadataKeyWasUserEntered: true,
            Self.batchIDKey: batchID,
            Self.sampleKindKey: "workout",
            "io.tuist.generate-sleep-data.session-index": index,
            "io.tuist.generate-sleep-data.workout-kind": session.kind.rawValue,
        ])

        var samples: [HKSample] = []

        if session.kilocalories > 0,
           let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            let energy = HKQuantity(unit: .kilocalorie(), doubleValue: session.kilocalories)
            samples.append(
                HKQuantitySample(
                    type: energyType,
                    quantity: energy,
                    start: session.start,
                    end: session.end
                )
            )
        }

        if let distanceMeters = session.distanceMeters,
           distanceMeters > 0,
           let distanceType = distanceQuantityType(for: session.kind) {
            let distance = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
            samples.append(
                HKQuantitySample(
                    type: distanceType,
                    quantity: distance,
                    start: session.start,
                    end: session.end
                )
            )
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        try await builder.endCollection(at: session.end)
        _ = try await builder.finishWorkout()
    }

    private func activityType(for kind: WorkoutKind) -> HKWorkoutActivityType {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .cycling:
            return .cycling
        case .strength:
            return .functionalStrengthTraining
        case .hiking:
            return .hiking
        case .yoga:
            return .yoga
        case .swimming:
            return .swimming
        }
    }

    private func distanceQuantityType(for kind: WorkoutKind) -> HKQuantityType? {
        guard let distanceKind = kind.distanceKind else {
            return nil
        }

        let identifier: HKQuantityTypeIdentifier
        switch distanceKind {
        case .walkingRunning:
            identifier = .distanceWalkingRunning
        case .cycling:
            identifier = .distanceCycling
        case .swimming:
            identifier = .distanceSwimming
        }

        return HKObjectType.quantityType(forIdentifier: identifier)
    }

    private func sampleType(for mode: HealthDataMode) -> HKSampleType? {
        switch mode {
        case .sleep:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .hrv:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .workout:
            return HKObjectType.workoutType()
        case .steps:
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        }
    }

    private func requireSampleType(for mode: HealthDataMode) throws -> HKSampleType {
        guard let sampleType = sampleType(for: mode) else {
            switch mode {
            case .sleep:
                throw HealthStoreError.sleepTypeUnavailable
            case .hrv:
                throw HealthStoreError.hrvTypeUnavailable
            case .workout:
                throw HealthStoreError.workoutTypeUnavailable
            case .steps:
                throw HealthStoreError.stepTypeUnavailable
            }
        }

        return sampleType
    }

    private func shareTypes(for mode: HealthDataMode) throws -> Set<HKSampleType> {
        switch mode {
        case .sleep, .hrv, .steps:
            return [try requireSampleType(for: mode)]
        case .workout:
            var types: Set<HKSampleType> = [HKObjectType.workoutType()]
            let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
                .activeEnergyBurned,
                .distanceWalkingRunning,
                .distanceCycling,
                .distanceSwimming,
            ]
            for identifier in quantityIdentifiers {
                if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                    types.insert(type)
                }
            }
            return types
        }
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

    private func requireStepType() throws -> HKQuantityType {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthStoreError.stepTypeUnavailable
        }

        return stepType
    }

    private func makeStepSamples(
        for sessions: [StepDaySession],
        stepType: HKQuantityType,
        batchID: String
    ) -> [HKQuantitySample] {
        sessions.enumerated().flatMap { dayIndex, session in
            session.samples.enumerated().map { hourIndex, sample in
                HKQuantitySample(
                    type: stepType,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(sample.steps)),
                    start: sample.interval.start,
                    end: sample.interval.end,
                    metadata: [
                        HKMetadataKeyWasUserEntered: true,
                        Self.batchIDKey: batchID,
                        Self.sampleKindKey: "stepCount",
                        "io.tuist.generate-sleep-data.day-index": dayIndex,
                        "io.tuist.generate-sleep-data.hour-index": hourIndex,
                    ]
                )
            }
        }
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

    private func logHRVWrite(batchID: String, request: HRVWriteRequest, sampleCount: Int) {
        print(
            """
            [HealthWrite][HRV] preparing save.
            batchID=\(batchID)
            preset=\(request.preset.rawValue)
            state=\(request.preset.title)
            recordDate=\(Self.consoleDateFormatter.string(from: request.recordDate))
            sampleTime=\(Self.consoleTimeFormatter.string(from: request.sampleTime))
            days=\(request.days)
            baselineMilliseconds=\(request.valueMilliseconds)
            sampleCount=\(sampleCount)
            """
        )
    }

    private func logWorkoutWrite(
        batchID: String,
        request: WorkoutGenerationRequest,
        sessions: [WorkoutSession]
    ) {
        print(
            """
            [HealthWrite][Workout] preparing save.
            batchID=\(batchID)
            endDate=\(Self.consoleDateFormatter.string(from: request.endDate))
            days=\(request.days)
            workoutsPerWeek=\(request.workoutsPerWeek)
            workoutCount=\(sessions.count)
            """
        )
    }

    private func logStepWrite(
        batchID: String,
        request: StepGenerationRequest,
        sessions: [StepDaySession],
        sampleCount: Int
    ) {
        print(
            """
            [HealthWrite][Steps] preparing save.
            batchID=\(batchID)
            endDate=\(Self.consoleDateFormatter.string(from: request.endDate))
            days=\(request.days)
            averageStepsPerDay=\(request.averageStepsPerDay)
            dayCount=\(sessions.count)
            sampleCount=\(sampleCount)
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
