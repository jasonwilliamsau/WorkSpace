// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EdgeWorkDashboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EdgeWorkDashboard", targets: ["EdgeWorkDashboard"])
    ],
    targets: [
        .executableTarget(
            name: "EdgeWorkDashboard",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "EdgeWorkDashboardTests",
            dependencies: ["EdgeWorkDashboard"]
        )
    ]
)
