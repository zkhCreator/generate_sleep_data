import ProjectDescription

let project = Project(
    name: "generate_sleep_data",
    targets: [
        .target(
            name: "generate_sleep_data",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.generate-sleep-data",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["generate_sleep_data/Sources/**"],
            resources: ["generate_sleep_data/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "generate_sleep_dataTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.generate-sleep-dataTests",
            infoPlist: .default,
            sources: ["generate_sleep_data/Tests/**"],
            resources: [],
            dependencies: [.target(name: "generate_sleep_data")]
        ),
    ]
)
