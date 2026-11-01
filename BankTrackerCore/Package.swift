// swift-tools-version: 6.0
import PackageDescription

// Platform-independent logic for Bank Tracker: offer terms, eligibility checks,
// bonus timelines, tax forms and statistics. No UI or persistence code lives here,
// so it can be shared by the macOS, iOS and iPadOS apps and tested with `swift test`.
let package = Package(
    name: "BankTrackerCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "BankTrackerCore", targets: ["BankTrackerCore"]),
    ],
    targets: [
        .target(name: "BankTrackerCore"),
        .testTarget(name: "BankTrackerCoreTests", dependencies: ["BankTrackerCore"]),
    ]
)
