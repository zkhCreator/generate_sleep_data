/// Purpose:
/// Root SwiftUI screen for quickly configuring and writing sleep or HRV data into Health.
///
/// Responsibilities:
/// Present the mode switcher and mode-specific forms, surface authorization
/// state, and trigger the view model's async actions.
///
/// Non-Goals:
/// This file does not talk to HealthKit directly or own the date-calculation rules.
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SleepDataViewModel()
    @State private var isShowingDeleteConfirmation = false

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                Section("数据类型") {
                    Picker("数据类型", selection: modeBinding) {
                        ForEach(HealthDataMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Health 权限") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: viewModel.authorizationIconName)
                            .font(.title3)
                            .foregroundStyle(viewModel.authorizationTint)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.authorizationTitle)
                                .font(.headline)
                            Text(viewModel.authorizationDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("仅授权 Health") {
                        Task {
                            await viewModel.requestHealthAccess()
                        }
                    }
                    .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
                }

                if viewModel.showsSleepControls {
                    sleepSections
                }

                if viewModel.showsHRVControls {
                    hrvSections
                }

                if viewModel.showsRestingHeartRateControls {
                    restingHeartRateSections
                }

                if viewModel.showsWorkoutControls {
                    workoutSections
                }

                if viewModel.showsStepControls {
                    stepSections
                }

                if viewModel.showsMenstrualControls {
                    menstrualSections
                }

                if let statusMessage = viewModel.statusMessage {
                    Section("结果") {
                        Text(statusMessage)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(viewModel.navigationTitle)
        }
        .task {
            viewModel.refreshAuthorizationState()
        }
        .confirmationDialog(
            "清除当前范围数据？",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    await viewModel.deleteCurrentRangeData()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(viewModel.clearConfirmationMessage)
        }
    }

    @ViewBuilder
    private var sleepSections: some View {
        Section("快速预设") {
            ForEach(QuickPreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            DatePicker(
                viewModel.sleepDateTitle,
                selection: sleepDateBinding,
                displayedComponents: [.date]
            )

            DatePicker(
                "上床时间",
                selection: bedtimeTimeBinding,
                displayedComponents: [.hourAndMinute]
            )

            Stepper(value: nightsBinding, in: 1...365) {
                LabeledContent("生成晚数", value: "\(viewModel.request.nights) 晚")
            }

            Stepper(value: sleepDurationBinding, in: 60...720, step: 15) {
                LabeledContent("睡眠时长", value: viewModel.sleepDurationText)
            }

            Stepper(value: sleepLatencyBinding, in: 0...90, step: 5) {
                LabeledContent("入睡耗时", value: viewModel.sleepLatencyText)
            }

            Stepper(value: overnightAwakeBinding, in: 0...120, step: 5) {
                LabeledContent("夜间清醒", value: viewModel.overnightAwakeText)
            }

            Text(viewModel.scheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("睡眠分期预览") {
            Text(viewModel.stageSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("每一晚会写入 1 条 inBed sample，再写入若干条 awake/core/deep/REM 分期 sample。清除入口只会删除当前范围内由本 app 写入的数据，不会生成或删除心率、血氧等其它健康数据。")
        }
    }

    @ViewBuilder
    private var hrvSections: some View {
        Section("快速预设") {
            ForEach(HRVRangePreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            Picker("HRV 档位", selection: hrvPresetBinding) {
                ForEach(HRVPreset.allCases) { preset in
                    Text(preset.segmentTitle).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            DatePicker(
                "记录时间",
                selection: hrvTimeBinding,
                displayedComponents: [.hourAndMinute]
            )

            Stepper(value: hrvDaysBinding, in: 1...365) {
                LabeledContent("覆盖天数", value: "\(viewModel.hrvRequest.days) 天")
            }

            LabeledContent("基准 HRV", value: viewModel.hrvValueText)

            Text(viewModel.hrvSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("会按所选天数，每天写入 1 条 heartRateVariabilitySDNN sample（单位 ms），数值围绕所选档位的基准值逐日波动。清除入口只会删除当前范围内由本 app 写入的 HRV 数据。")
        }
    }

    @ViewBuilder
    private var restingHeartRateSections: some View {
        Section("快速预设") {
            ForEach(RestingHeartRatePreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            DatePicker(
                "最后一天",
                selection: restingHeartRateEndDateBinding,
                displayedComponents: [.date]
            )

            DatePicker(
                "记录时间",
                selection: restingHeartRateTimeBinding,
                displayedComponents: [.hourAndMinute]
            )

            Stepper(value: restingHeartRateDaysBinding, in: 1...365) {
                LabeledContent("覆盖天数", value: "\(viewModel.restingHeartRateRequest.days) 天")
            }

            Stepper(value: averageRestingHeartRateBinding, in: 40...120) {
                LabeledContent("静息心率", value: "\(viewModel.restingHeartRateRequest.averageBeatsPerMinute) 次/分")
            }

            Text(viewModel.restingHeartRateScheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("会按所选天数，每天写入 1 条 restingHeartRate sample（单位 次/分），数值围绕设定的基准值逐日波动。清除入口只会删除当前范围内由本 app 写入的静息心率记录。")
        }
    }

    @ViewBuilder
    private var workoutSections: some View {
        Section("快速预设") {
            ForEach(WorkoutPreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            DatePicker(
                "最后一天",
                selection: workoutEndDateBinding,
                displayedComponents: [.date]
            )

            Stepper(value: workoutDaysBinding, in: 1...365) {
                LabeledContent("覆盖天数", value: "\(viewModel.workoutRequest.days) 天")
            }

            Stepper(value: workoutsPerWeekBinding, in: 1...7) {
                LabeledContent("每周锻炼", value: "\(viewModel.workoutRequest.workoutsPerWeek) 次")
            }

            Text(viewModel.workoutScheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("锻炼类型分布") {
            Text(viewModel.workoutBreakdown)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("会按每周固定次数，在所选天数内自动轮换跑步 / 步行 / 骑行 / 力量训练 / 徒步 / 瑜伽 / 游泳等锻炼，并写入活动能量与距离。清除入口只会删除当前范围内由本 app 写入的锻炼记录。生成 1 年数据需要写入约 200 条锻炼，过程可能需要数十秒。")
        }
    }

    @ViewBuilder
    private var stepSections: some View {
        Section("快速预设") {
            ForEach(StepPreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            DatePicker(
                "最后一天",
                selection: stepEndDateBinding,
                displayedComponents: [.date]
            )

            Stepper(value: stepDaysBinding, in: 1...365) {
                LabeledContent("覆盖天数", value: "\(viewModel.stepRequest.days) 天")
            }

            Stepper(value: averageStepsBinding, in: 1000...30000, step: 500) {
                LabeledContent("日均步数", value: "\(viewModel.stepRequest.averageStepsPerDay) 步")
            }

            Text(viewModel.stepScheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("会在所选天数内，按日均步数生成每天 08:00–22:00 的逐小时 stepCount sample（周末略微上调），并写入到 Apple Health。清除入口只会删除当前范围内由本 app 写入的步数记录。生成 1 年数据需要写入数千条 sample，过程可能需要数十秒。")
        }
    }

    @ViewBuilder
    private var menstrualSections: some View {
        Section("快速预设") {
            ForEach(MenstrualPreset.allCases) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title)
                            .font(.headline)
                        Text(preset.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section("生成参数") {
            DatePicker(
                "最后一天",
                selection: menstrualEndDateBinding,
                displayedComponents: [.date]
            )

            Stepper(value: menstrualDaysBinding, in: 7...365) {
                LabeledContent("覆盖天数", value: "\(viewModel.menstrualRequest.days) 天")
            }

            Stepper(value: cycleLengthBinding, in: 21...35) {
                LabeledContent("周期长度", value: "\(viewModel.menstrualRequest.cycleLength) 天")
            }

            Stepper(value: periodLengthBinding, in: 2...10) {
                LabeledContent("经期长度", value: "\(viewModel.menstrualRequest.periodLength) 天")
            }

            Text(viewModel.menstrualScheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                Task {
                    await viewModel.performPrimaryAction()
                }
            } label: {
                actionLabel
            }
            .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)

            if viewModel.showsClearButton {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(viewModel.clearButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isWorking || viewModel.authorizationState == .unavailable)
            }
        } footer: {
            Text("会按所选周期长度，在覆盖天数内生成多个经期，每天写入 1 条 menstrualFlow 记录（少量 / 中等 / 大量），并标记每个周期的第一天。周期与经期长度会逐周期轻微波动。清除入口只会删除当前范围内由本 app 写入的经期记录。")
        }
    }

    @ViewBuilder
    private var actionLabel: some View {
        if viewModel.isWorking {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            Text(viewModel.primaryButtonTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
    }

    private var modeBinding: Binding<HealthDataMode> {
        Binding(
            get: { viewModel.selectedMode },
            set: { viewModel.setSelectedMode($0) }
        )
    }

    private var sleepDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.request.sleepDate },
            set: { viewModel.request.sleepDate = $0 }
        )
    }

    private var bedtimeTimeBinding: Binding<Date> {
        Binding(
            get: { viewModel.request.bedtimeTime },
            set: { viewModel.request.bedtimeTime = $0 }
        )
    }

    private var nightsBinding: Binding<Int> {
        Binding(
            get: { viewModel.request.nights },
            set: { viewModel.request.nights = $0 }
        )
    }

    private var sleepDurationBinding: Binding<Int> {
        Binding(
            get: { viewModel.request.sleepDurationMinutes },
            set: { viewModel.request.sleepDurationMinutes = $0 }
        )
    }

    private var sleepLatencyBinding: Binding<Int> {
        Binding(
            get: { viewModel.request.sleepLatencyMinutes },
            set: { viewModel.request.sleepLatencyMinutes = $0 }
        )
    }

    private var overnightAwakeBinding: Binding<Int> {
        Binding(
            get: { viewModel.request.overnightAwakeMinutes },
            set: { viewModel.request.overnightAwakeMinutes = $0 }
        )
    }

    private var hrvTimeBinding: Binding<Date> {
        Binding(
            get: { viewModel.hrvRequest.sampleTime },
            set: { viewModel.hrvRequest.sampleTime = $0 }
        )
    }

    private var hrvPresetBinding: Binding<HRVPreset> {
        Binding(
            get: { viewModel.hrvRequest.preset },
            set: { viewModel.hrvRequest.preset = $0 }
        )
    }

    private var hrvDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.hrvRequest.days },
            set: { viewModel.hrvRequest.days = $0 }
        )
    }

    private var restingHeartRateEndDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.restingHeartRateRequest.endDate },
            set: { viewModel.restingHeartRateRequest.endDate = $0 }
        )
    }

    private var restingHeartRateTimeBinding: Binding<Date> {
        Binding(
            get: { viewModel.restingHeartRateRequest.sampleTime },
            set: { viewModel.restingHeartRateRequest.sampleTime = $0 }
        )
    }

    private var restingHeartRateDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.restingHeartRateRequest.days },
            set: { viewModel.restingHeartRateRequest.days = $0 }
        )
    }

    private var averageRestingHeartRateBinding: Binding<Int> {
        Binding(
            get: { viewModel.restingHeartRateRequest.averageBeatsPerMinute },
            set: { viewModel.restingHeartRateRequest.averageBeatsPerMinute = $0 }
        )
    }

    private var workoutEndDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.workoutRequest.endDate },
            set: { viewModel.workoutRequest.endDate = $0 }
        )
    }

    private var workoutDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.workoutRequest.days },
            set: { viewModel.workoutRequest.days = $0 }
        )
    }

    private var workoutsPerWeekBinding: Binding<Int> {
        Binding(
            get: { viewModel.workoutRequest.workoutsPerWeek },
            set: { viewModel.workoutRequest.workoutsPerWeek = $0 }
        )
    }

    private var stepEndDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.stepRequest.endDate },
            set: { viewModel.stepRequest.endDate = $0 }
        )
    }

    private var stepDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.stepRequest.days },
            set: { viewModel.stepRequest.days = $0 }
        )
    }

    private var averageStepsBinding: Binding<Int> {
        Binding(
            get: { viewModel.stepRequest.averageStepsPerDay },
            set: { viewModel.stepRequest.averageStepsPerDay = $0 }
        )
    }

    private var menstrualEndDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.menstrualRequest.endDate },
            set: { viewModel.menstrualRequest.endDate = $0 }
        )
    }

    private var menstrualDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.menstrualRequest.days },
            set: { viewModel.menstrualRequest.days = $0 }
        )
    }

    private var cycleLengthBinding: Binding<Int> {
        Binding(
            get: { viewModel.menstrualRequest.cycleLength },
            set: { viewModel.menstrualRequest.cycleLength = $0 }
        )
    }

    private var periodLengthBinding: Binding<Int> {
        Binding(
            get: { viewModel.menstrualRequest.periodLength },
            set: { viewModel.menstrualRequest.periodLength = $0 }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
