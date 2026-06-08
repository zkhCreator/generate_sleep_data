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
let automaticSigningSettings: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": .string(developmentTeam),
    "SWIFT_EMIT_LOC_STRINGS": "YES",
  ]
let deploymentTargets: DeploymentTargets = .iOS("17.0")

let project = Project(
    name: "generate_sleep_data",
    targets: [
        .target(
            name: "generate_sleep_data",
            destinations: .iOS,
            product: .app,
            bundleId: "com.laterwork.generate.health.data",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": .string(displayName),
                    "NSHealthShareUsageDescription": "需要读取 Health 中与你授权的睡眠、HRV、静息心率、锻炼、步数和经期记录状态，用于确认权限状态并校验写入结果。",
                    "NSHealthUpdateUsageDescription": "需要将生成的 sleep data、HRV、静息心率、锻炼、步数和经期记录写入 Health，便于快速构造测试用健康记录。",
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
                base: automaticSigningSettings
            )
        ),
        .target(
            name: "generate_sleep_dataTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.laterwork.generate.health.dataTests",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: ["generate_sleep_data/Tests/**"],
            resources: [],
            dependencies: [.target(name: "generate_sleep_data")],
            settings: .settings(
                base: automaticSigningSettings
            )
        ),
    ]
)
