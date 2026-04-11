// Purpose:
// Tuist project definition for the Health data generator app.
//
// Responsibilities:
// Declare the iOS app target, wire the HealthKit entitlement, and provide the
// privacy strings, signing settings, app display name, and export-compliance
// metadata required to write sleep and HRV samples into Apple Health.
//
// Non-Goals:
// This file does not describe runtime behavior or business logic.
import ProjectDescription

let developmentTeam = "8AGTSQVX42"
let displayName = "health 数据刷入"
let baseSigningSettings: SettingsDictionary = [
    "CODE_SIGN_STYLE": .string("Automatic"),
    "DEVELOPMENT_TEAM": .string(developmentTeam),
]

let project = Project(
    name: "generate_sleep_data",
    targets: [
        .target(
            name: "generate_sleep_data",
            destinations: .iOS,
            product: .app,
            bundleId: "com.laterwork.generate.health.data",
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": .string(displayName),
                    "NSHealthUpdateUsageDescription": "需要将生成的 sleep data 和 HRV 写入 Health，便于快速构造测试用健康记录。",
                    "ITSAppUsesNonExemptEncryption": .boolean(false),
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["generate_sleep_data/Sources/**"],
            resources: ["generate_sleep_data/Resources/**"],
            entitlements: .file(path: "generate_sleep_data/generate_sleep_data.entitlements"),
            dependencies: [],
            settings: .settings(
                base: baseSigningSettings
            )
        ),
        .target(
            name: "generate_sleep_dataTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.laterwork.generate.health.dataTests",
            infoPlist: .default,
            sources: ["generate_sleep_data/Tests/**"],
            resources: [],
            dependencies: [.target(name: "generate_sleep_data")],
            settings: .settings(
                base: baseSigningSettings
            )
        ),
    ]
)
