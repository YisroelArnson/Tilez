// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tilez",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tilez", targets: ["Tilez"])],
    targets: [
        .target(name: "TilezCore"),
        .target(name: "TilezSpacesBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
        .executableTarget(name: "Tilez", dependencies: ["TilezCore", "TilezSpacesBridge"]),
        .executableTarget(name: "TilezCoreChecks", dependencies: ["TilezCore"], path: "Tests/TilezCoreTests")
    ]
)
