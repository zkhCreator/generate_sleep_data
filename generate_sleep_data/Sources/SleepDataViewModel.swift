/// Purpose:
/// UI-facing state and actions for the one-screen Health data generator.
///
/// Responsibilities:
/// Hold editable sleep and HRV parameters, translate authorization and write
/// results into user-facing text, and keep SwiftUI free from direct HealthKit
/// calls.
///
/// Inputs and Outputs:
/// Inputs are form edits and async responses from `HealthDataWriting`. Outputs
/// are published view state, status messages, and human-readable summaries.
///
/// Non-Goals:
/// This file does not define layout or perform the actual HealthKit persistence.
import SwiftUI

@MainActor
final class SleepDataViewModel: ObservableObject {
    @Published var selectedMode: HealthDataMode
    @Published var request: SleepGenerationRequest
    @Published var hrvRequest: HRVWriteRequest
    @Published var workoutRequest: WorkoutGenerationRequest
    @Published var stepRequest: StepGenerationRequest
    @Published var menstrualRequest: MenstrualGenerationRequest
    @Published private(set) var authorizationState: HealthAuthorizationState
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    private let healthStore: HealthDataWriting
    private let calendar: Calendar
    private let now: () -> Date

    init(
        healthStore: HealthDataWriting = HealthKitStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
        self.now = now
        self.selectedMode = .sleep
        self.request = SleepGenerationRequest.default(calendar: calendar, now: now())
        self.hrvRequest = HRVWriteRequest.default(calendar: calendar, now: now())
        self.workoutRequest = WorkoutGenerationRequest.default(calendar: calendar, now: now())
        self.stepRequest = StepGenerationRequest.default(calendar: calendar, now: now())
        self.menstrualRequest = MenstrualGenerationRequest.default(calendar: calendar, now: now())
        self.authorizationState = healthStore.authorizationStatus(for: .sleep)
    }

    var navigationTitle: String {
        selectedMode.navigationTitle
    }

    var authorizationIconName: String {
        switch authorizationState {
        case .sharingAuthorized:
            return "checkmark.shield.fill"
        case .sharingDenied:
            return "exclamationmark.shield.fill"
        case .notDetermined:
            return "heart.text.square.fill"
        case .unavailable:
            return "iphone.slash"
        }
    }

    var authorizationTint: Color {
        switch authorizationState {
        case .sharingAuthorized:
            return .green
        case .sharingDenied:
            return .orange
        case .notDetermined:
            return .blue
        case .unavailable:
            return .secondary
        }
    }

    var authorizationTitle: String {
        switch authorizationState {
        case .sharingAuthorized:
            return "已获得 Health 写入权限"
        case .sharingDenied:
            return "Health 写入权限被拒绝"
        case .notDetermined:
            return "尚未请求 Health 权限"
        case .unavailable:
            return "当前环境无法使用 HealthKit"
        }
    }

    var authorizationDescription: String {
        switch authorizationState {
        case .sharingAuthorized:
            switch selectedMode {
            case .sleep:
                return "现在可以把生成的 sleep data 直接写入到 Apple Health。"
            case .hrv:
                return "现在可以把今天的 HRV 直接写入到 Apple Health。"
            case .workout:
                return "现在可以把生成的锻炼记录直接写入到 Apple Health。"
            case .steps:
                return "现在可以把生成的步数记录直接写入到 Apple Health。"
            case .menstrual:
                return "现在可以把生成的经期记录直接写入到 Apple Health。"
            }
        case .sharingDenied:
            return "请到系统设置里的 Health 权限页重新打开写入权限。"
        case .notDetermined:
            switch selectedMode {
            case .sleep:
                return "首次写入前会弹出系统授权框，只申请 sleepAnalysis 写入权限。"
            case .hrv:
                return "首次写入前会弹出系统授权框，只申请 heartRateVariabilitySDNN 写入权限。"
            case .workout:
                return "首次写入前会弹出系统授权框，申请 workout、活动能量与距离的写入权限。"
            case .steps:
                return "首次写入前会弹出系统授权框，只申请 stepCount 写入权限。"
            case .menstrual:
                return "首次写入前会弹出系统授权框，只申请 menstrualFlow 写入权限。"
            }
        case .unavailable:
            return "HealthKit 不支持当前运行环境。请在已开启 Health 的 iPhone 真机上运行。"
        }
    }

    var primaryButtonTitle: String {
        switch selectedMode {
        case .sleep:
            return authorizationState.isAuthorized ? "写入到 Health" : "授权并写入到 Health"
        case .hrv:
            return authorizationState.isAuthorized ? "写入今天的 HRV" : "授权并写入今天的 HRV"
        case .workout:
            return authorizationState.isAuthorized ? "写入锻炼记录到 Health" : "授权并写入锻炼记录到 Health"
        case .steps:
            return authorizationState.isAuthorized ? "写入步数记录到 Health" : "授权并写入步数记录到 Health"
        case .menstrual:
            return authorizationState.isAuthorized ? "写入经期记录到 Health" : "授权并写入经期记录到 Health"
        }
    }

    var clearButtonTitle: String {
        "清除当前范围数据"
    }

    var showsSleepControls: Bool {
        selectedMode == .sleep
    }

    var showsHRVControls: Bool {
        selectedMode == .hrv
    }

    var showsWorkoutControls: Bool {
        selectedMode == .workout
    }

    var showsStepControls: Bool {
        selectedMode == .steps
    }

    var showsMenstrualControls: Bool {
        selectedMode == .menstrual
    }

    var showsClearButton: Bool {
        true
    }

    var sleepDateTitle: String {
        request.nights > 1 ? "最后一晚睡眠日期" : "睡眠日期"
    }

    var sleepDurationText: String {
        Self.durationText(minutes: request.sleepDurationMinutes)
    }

    var sleepLatencyText: String {
        request.sleepLatencyMinutes == 0 ? "立即入睡" : "\(request.sleepLatencyMinutes) 分钟"
    }

    var overnightAwakeText: String {
        request.overnightAwakeMinutes == 0 ? "无夜间清醒" : "\(request.overnightAwakeMinutes) 分钟"
    }

    var scheduleSummary: String {
        let sessions = request.makeSessions(calendar: calendar)
        guard let first = sessions.first, let last = sessions.last else {
            return "请至少生成 1 晚，且睡眠时长大于 0 分钟。"
        }

        let rangeText = "\(Self.dateTimeFormatter.string(from: first.bedtime)) 到 \(Self.dateTimeFormatter.string(from: last.wakeTime))"
        let sampleCount = sessions.reduce(0) { $0 + $1.sampleCount }
        return "将写入 \(sessions.count) 晚，共 \(sampleCount) 条 sample。时间范围：\(rangeText)。"
    }

    var stageSummary: String {
        let sessions = request.makeSessions(calendar: calendar)
        guard !sessions.isEmpty else {
            return "Awake 0 分钟 · Core 0 分钟 · Deep 0 分钟 · REM 0 分钟"
        }

        let totals = sessions.reduce(into: [SleepStage: Int]()) { partialResult, session in
            for stage in SleepStage.allCases {
                partialResult[stage, default: 0] += session.totalMinutes(for: stage)
            }
        }

        return SleepStage.allCases
            .map { "\($0.title) \(Self.durationText(minutes: totals[$0, default: 0]))" }
            .joined(separator: " · ")
    }

    var hrvValueText: String {
        "\(Int(hrvRequest.valueMilliseconds)) ms"
    }

    var hrvSummary: String {
        let request = currentHRVRequest
        let samples = request.makeSamples(calendar: calendar)
        guard let first = samples.first, let last = samples.last else {
            return "请至少生成 1 天的 HRV。"
        }

        if samples.count == 1 {
            return "今天将写入 1 条 HRV sample。记录时间：\(Self.dateTimeFormatter.string(from: last.date))。档位：\(hrvRequest.preset.title)（基准 \(hrvValueText)）。"
        }

        let rangeText = "\(Self.dateFormatter.string(from: first.date)) 到 \(Self.dateFormatter.string(from: last.date))"
        return "将写入 \(samples.count) 条 HRV sample（每天 1 条，围绕基准 \(hrvValueText) 波动）。时间范围：\(rangeText)。档位：\(hrvRequest.preset.title)。"
    }

    var workoutScheduleSummary: String {
        let sessions = workoutRequest.makeSessions(calendar: calendar)
        guard let first = sessions.first, let last = sessions.last else {
            return "请至少生成 1 天，且每周锻炼次数大于 0。"
        }

        let totalKilocalories = Int(sessions.reduce(0) { $0 + $1.kilocalories }.rounded())
        let rangeText = "\(Self.dateFormatter.string(from: first.start)) 到 \(Self.dateFormatter.string(from: last.end))"
        return "将写入 \(sessions.count) 次锻炼，总计约 \(totalKilocalories) 千卡。时间范围：\(rangeText)。"
    }

    var workoutBreakdown: String {
        let sessions = workoutRequest.makeSessions(calendar: calendar)
        guard !sessions.isEmpty else {
            return "暂无锻炼记录"
        }

        let counts = sessions.reduce(into: [WorkoutKind: Int]()) { partialResult, session in
            partialResult[session.kind, default: 0] += 1
        }

        return WorkoutKind.allCases
            .filter { counts[$0, default: 0] > 0 }
            .map { "\($0.title) \(counts[$0, default: 0]) 次" }
            .joined(separator: " · ")
    }

    var stepScheduleSummary: String {
        let sessions = stepRequest.makeSessions(calendar: calendar)
        guard let first = sessions.first?.samples.first?.interval.start,
              let last = sessions.last?.samples.last?.interval.end else {
            return "请至少生成 1 天，且日均步数大于 0。"
        }

        let totalSteps = sessions.reduce(0) { $0 + $1.totalSteps }
        let sampleCount = sessions.reduce(0) { $0 + $1.sampleCount }
        let rangeText = "\(Self.dateFormatter.string(from: first)) 到 \(Self.dateFormatter.string(from: last))"
        return "将写入 \(sessions.count) 天、共 \(sampleCount) 条 sample，总计约 \(totalSteps) 步。时间范围：\(rangeText)。"
    }

    var menstrualScheduleSummary: String {
        let samples = menstrualRequest.makeSamples(calendar: calendar)
        guard let first = samples.first, let last = samples.last else {
            return "请检查天数、周期长度和经期长度。"
        }

        let cycleCount = samples.filter(\.isCycleStart).count
        let rangeText = "\(Self.dateFormatter.string(from: first.date)) 到 \(Self.dateFormatter.string(from: last.date))"
        return "将写入 \(cycleCount) 个周期、共 \(samples.count) 天经期记录。时间范围：\(rangeText)。"
    }

    var clearConfirmationMessage: String {
        switch selectedMode {
        case .hrv:
            return "会删除当前时间范围内、由本 app 写入的 HRV 数据。不会影响其他来源的 HRV 记录。\(hrvRequestRangeText)"
        case .workout:
            return "会删除当前时间范围内、由本 app 写入的锻炼记录。不会影响其他来源的运动数据。\(workoutRequestRangeText)"
        case .steps:
            return "会删除当前时间范围内、由本 app 写入的步数记录。不会影响其他来源的步数数据。\(stepRequestRangeText)"
        case .menstrual:
            return "会删除当前时间范围内、由本 app 写入的经期记录。不会影响其他来源的经期数据。\(menstrualRequestRangeText)"
        default:
            return "会删除当前时间范围内、由本 app 写入的 sleepAnalysis 数据。不会影响其他来源的睡眠记录。\(sleepRequestRangeText)"
        }
    }

    func setSelectedMode(_ mode: HealthDataMode) {
        selectedMode = mode
        if mode == .hrv {
            hrvRequest.recordDate = calendar.startOfDay(for: now())
        }
        if mode == .workout {
            workoutRequest.endDate = calendar.startOfDay(for: now())
        }
        if mode == .steps {
            stepRequest.endDate = calendar.startOfDay(for: now())
        }
        if mode == .menstrual {
            menstrualRequest.endDate = calendar.startOfDay(for: now())
        }
        authorizationState = healthStore.authorizationStatus(for: mode)
        statusMessage = nil
    }

    func refreshAuthorizationState() {
        authorizationState = healthStore.authorizationStatus(for: selectedMode)
    }

    func apply(_ preset: QuickPreset) {
        preset.apply(to: &request, calendar: calendar, now: now())
        statusMessage = nil
    }

    func apply(_ preset: HRVRangePreset) {
        preset.apply(to: &hrvRequest, calendar: calendar, now: now())
        statusMessage = nil
    }

    func apply(_ preset: WorkoutPreset) {
        preset.apply(to: &workoutRequest, calendar: calendar, now: now())
        statusMessage = nil
    }

    func apply(_ preset: StepPreset) {
        preset.apply(to: &stepRequest, calendar: calendar, now: now())
        statusMessage = nil
    }

    func apply(_ preset: MenstrualPreset) {
        preset.apply(to: &menstrualRequest, calendar: calendar, now: now())
        statusMessage = nil
    }

    func requestHealthAccess() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            authorizationState = try await healthStore.requestAuthorization(for: selectedMode)
            statusMessage = authorizationState.isAuthorized ? "Health 写入权限已就绪。" : "Health 写入权限仍未开启。"
        } catch {
            authorizationState = healthStore.authorizationStatus(for: selectedMode)
            statusMessage = error.localizedDescription
        }
    }

    func performPrimaryAction() async {
        switch selectedMode {
        case .sleep:
            await generateSleepData()
        case .hrv:
            await writeHRVData()
        case .workout:
            await generateWorkoutData()
        case .steps:
            await generateStepData()
        case .menstrual:
            await generateMenstrualData()
        }
    }

    func deleteCurrentRangeData() async {
        switch selectedMode {
        case .hrv:
            await deleteHRVData()
        case .workout:
            await deleteWorkoutData()
        case .steps:
            await deleteStepData()
        case .menstrual:
            await deleteMenstrualData()
        default:
            await deleteSleepData()
        }
    }

    func generateSleepData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .sleep)

            let result = try await healthStore.writeSleepData(for: request)
            statusMessage = "已写入 \(result.sessionCount) 晚睡眠（\(result.sampleCount) 条 sample）。\(sleepRequestRangeText)。阶段汇总：\(stageSummary)。批次 ID：\(result.batchID.prefix(8))。"
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .sleep)
            statusMessage = error.localizedDescription
        }
    }

    func writeHRVData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .hrv)

            let result = try await healthStore.writeHRVData(for: currentHRVRequest)
            if result.sampleCount == 1 {
                statusMessage = "已写入今天的 HRV（1 条 sample）。记录时间：\(Self.dateTimeFormatter.string(from: result.lastDate))。基准：\(Int(result.baselineMilliseconds)) ms。"
            } else {
                let rangeText = "\(Self.dateFormatter.string(from: result.firstDate)) 到 \(Self.dateFormatter.string(from: result.lastDate))"
                statusMessage = "已写入 \(result.sampleCount) 条 HRV sample（围绕基准 \(Int(result.baselineMilliseconds)) ms 波动）。时间范围：\(rangeText)。批次 ID：\(result.batchID.prefix(8))。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .hrv)
            statusMessage = error.localizedDescription
        }
    }

    func generateWorkoutData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .workout)

            let result = try await healthStore.writeWorkoutData(for: workoutRequest)
            let rangeText = "\(Self.dateFormatter.string(from: result.firstStart)) 到 \(Self.dateFormatter.string(from: result.lastEnd))"
            statusMessage = "已写入 \(result.workoutCount) 次锻炼（总计约 \(Int(result.totalKilocalories.rounded())) 千卡）。时间范围：\(rangeText)。批次 ID：\(result.batchID.prefix(8))。"
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .workout)
            statusMessage = error.localizedDescription
        }
    }

    func deleteWorkoutData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .workout)

            let result = try await healthStore.deleteGeneratedWorkoutData(for: workoutRequest)
            if result.deletedWorkoutCount == 0 {
                statusMessage = "当前范围内没有找到由本 app 写入的锻炼记录。\(workoutRequestRangeText)。"
            } else {
                statusMessage = "已删除 \(result.deletedWorkoutCount) 次锻炼记录。\(workoutRequestRangeText)。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .workout)
            statusMessage = error.localizedDescription
        }
    }

    func deleteHRVData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .hrv)

            let result = try await healthStore.deleteGeneratedHRVData(for: currentHRVRequest)
            if result.deletedSampleCount == 0 {
                statusMessage = "当前范围内没有找到由本 app 写入的 HRV 数据。\(hrvRequestRangeText)。"
            } else {
                statusMessage = "已删除 \(result.deletedSampleCount) 条 HRV sample。\(hrvRequestRangeText)。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .hrv)
            statusMessage = error.localizedDescription
        }
    }

    func generateStepData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .steps)

            let result = try await healthStore.writeStepData(for: stepRequest)
            let rangeText = "\(Self.dateFormatter.string(from: result.firstStart)) 到 \(Self.dateFormatter.string(from: result.lastEnd))"
            statusMessage = "已写入 \(result.dayCount) 天步数（\(result.sampleCount) 条 sample，总计约 \(result.totalSteps) 步）。时间范围：\(rangeText)。批次 ID：\(result.batchID.prefix(8))。"
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .steps)
            statusMessage = error.localizedDescription
        }
    }

    func deleteStepData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .steps)

            let result = try await healthStore.deleteGeneratedStepData(for: stepRequest)
            if result.deletedSampleCount == 0 {
                statusMessage = "当前范围内没有找到由本 app 写入的步数记录。\(stepRequestRangeText)。"
            } else {
                statusMessage = "已删除 \(result.deletedSampleCount) 条步数 sample。\(stepRequestRangeText)。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .steps)
            statusMessage = error.localizedDescription
        }
    }

    func generateMenstrualData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .menstrual)

            let result = try await healthStore.writeMenstrualData(for: menstrualRequest)
            let rangeText = "\(Self.dateFormatter.string(from: result.firstDate)) 到 \(Self.dateFormatter.string(from: result.lastDate))"
            statusMessage = "已写入 \(result.cycleCount) 个周期、共 \(result.sampleCount) 天经期记录。时间范围：\(rangeText)。批次 ID：\(result.batchID.prefix(8))。"
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .menstrual)
            statusMessage = error.localizedDescription
        }
    }

    func deleteMenstrualData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .menstrual)

            let result = try await healthStore.deleteGeneratedMenstrualData(for: menstrualRequest)
            if result.deletedSampleCount == 0 {
                statusMessage = "当前范围内没有找到由本 app 写入的经期记录。\(menstrualRequestRangeText)。"
            } else {
                statusMessage = "已删除 \(result.deletedSampleCount) 天经期记录。\(menstrualRequestRangeText)。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .menstrual)
            statusMessage = error.localizedDescription
        }
    }

    func deleteSleepData() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await ensureAuthorization(for: .sleep)

            let result = try await healthStore.deleteGeneratedSleepData(for: request)
            if result.deletedSampleCount == 0 {
                statusMessage = "当前范围内没有找到由本 app 写入的 sleep data。\(sleepRequestRangeText)。"
            } else {
                statusMessage = "已删除 \(result.deletedSampleCount) 条 sleep sample。\(sleepRequestRangeText)。"
            }
        } catch {
            authorizationState = healthStore.authorizationStatus(for: .sleep)
            statusMessage = error.localizedDescription
        }
    }

    private func ensureAuthorization(for mode: HealthDataMode) async throws {
        if !authorizationState.isAuthorized || selectedMode != mode {
            authorizationState = try await healthStore.requestAuthorization(for: mode)
        }

        guard authorizationState.isAuthorized else {
            throw HealthStoreError.authorizationRequired
        }
    }

    private var currentHRVRequest: HRVWriteRequest {
        var request = hrvRequest
        request.recordDate = calendar.startOfDay(for: now())
        return request
    }

    private var sleepRequestRangeText: String {
        let sessions = request.makeSessions(calendar: calendar)
        guard let first = sessions.first, let last = sessions.last else {
            return "时间范围：未知"
        }

        return "时间范围：\(Self.dateTimeFormatter.string(from: first.bedtime)) 到 \(Self.dateTimeFormatter.string(from: last.wakeTime))"
    }

    private var hrvRequestRangeText: String {
        let samples = currentHRVRequest.makeSamples(calendar: calendar)
        guard let first = samples.first, let last = samples.last else {
            return "时间范围：未知"
        }

        return "时间范围：\(Self.dateFormatter.string(from: first.date)) 到 \(Self.dateFormatter.string(from: last.date))"
    }

    private var workoutRequestRangeText: String {
        let sessions = workoutRequest.makeSessions(calendar: calendar)
        guard let first = sessions.first, let last = sessions.last else {
            return "时间范围：未知"
        }

        return "时间范围：\(Self.dateFormatter.string(from: first.start)) 到 \(Self.dateFormatter.string(from: last.end))"
    }

    private var stepRequestRangeText: String {
        let sessions = stepRequest.makeSessions(calendar: calendar)
        guard let first = sessions.first?.samples.first?.interval.start,
              let last = sessions.last?.samples.last?.interval.end else {
            return "时间范围：未知"
        }

        return "时间范围：\(Self.dateFormatter.string(from: first)) 到 \(Self.dateFormatter.string(from: last))"
    }

    private var menstrualRequestRangeText: String {
        let samples = menstrualRequest.makeSamples(calendar: calendar)
        guard let first = samples.first, let last = samples.last else {
            return "时间范围：未知"
        }

        return "时间范围：\(Self.dateFormatter.string(from: first.date)) 到 \(Self.dateFormatter.string(from: last.date))"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static func durationText(minutes: Int) -> String {
        guard minutes > 0 else {
            return "0 分钟"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes) 分钟"
        }

        if remainingMinutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }
}
