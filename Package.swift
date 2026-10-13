// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrTouchBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "HerdrTouchBar", targets: ["HerdrTouchBar"]),
               .executable(name: "HerdrCoreChecks", targets: ["HerdrCoreChecks"])],
    targets: [
        .target(name: "HerdrCore"),
        .target(name: "TouchBarBridge", linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "HerdrTouchBar", dependencies: ["HerdrCore", "TouchBarBridge"],
                          linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "HerdrCoreChecks", dependencies: ["HerdrCore"], path: "Tests/HerdrCoreChecks")
    ],
    swiftLanguageModes: [.v5]
)
