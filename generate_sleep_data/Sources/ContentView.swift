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
                    await viewModel.deleteSleepData()
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

            Stepper(value: nightsBinding, in: 1...60) {
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
        Section("今天的 HRV") {
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

            LabeledContent("HRV 数值", value: viewModel.hrvValueText)

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
        } footer: {
            Text("会写入 1 条今天的 heartRateVariabilitySDNN sample，单位为毫秒（ms）。当前通过 segment 在过低 / 过高两种状态之间切换。")
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
