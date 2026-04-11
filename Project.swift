// Purpose:
// Tuist project definition for the Health data generator app.
//
// Responsibilities:
// Declare the iOS app target, wire the HealthKit entitlement, and provide the
// privacy strings and signing settings required to write sleep and HRV samples
// into Apple Health.
//
// Non-Goals:
// This file does not describe runtime behavior or business logic.
import ProjectDescription

let developmentTeam = "8AGTSQVX42"

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
                    "NSHealthUpdateUsageDescription": "需要将生成的 sleep data 和 HRV 写入 Health，便于快速构造测试用健康记录。",
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
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                ]
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
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                ]
            )
        ),
    ]
)
