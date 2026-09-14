// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowQuilt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WindowQuilt", targets: ["WindowQuilt"])],
    targets: [
        .target(name: "QuiltCore"),
        .target(name: "QuiltSpacesBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
        .executableTarget(name: "WindowQuilt", dependencies: ["QuiltCore", "QuiltSpacesBridge"]),
        .executableTarget(name: "QuiltCoreChecks", dependencies: ["QuiltCore"], path: "Tests/QuiltCoreTests")
    ]
)
