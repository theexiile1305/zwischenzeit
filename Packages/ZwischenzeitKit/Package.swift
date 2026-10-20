// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZwischenzeitKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "MockAPI", targets: ["MockAPI"]),
        .library(name: "LiveAPI", targets: ["LiveAPI"]),
        .library(name: "CalendarFeature", targets: ["CalendarFeature"]),
        .library(name: "AppointmentFeature", targets: ["AppointmentFeature"]),
        .library(name: "DocumentationFeature", targets: ["DocumentationFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "WatchSync", targets: ["WatchSync"]),
        .library(name: "WatchUI", targets: ["WatchUI"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "Domain"),
        .target(name: "MockAPI", dependencies: ["Domain"]),
        .target(name: "LiveAPI", dependencies: ["Domain"]),
        .target(name: "CalendarFeature", dependencies: ["Domain", "DesignSystem"]),
        .target(name: "DocumentationFeature", dependencies: ["Domain", "DesignSystem"]),
        .target(name: "AppointmentFeature", dependencies: ["Domain", "DesignSystem", "CalendarFeature", "DocumentationFeature"]),
        .target(name: "WatchSync", dependencies: ["Domain", "DesignSystem"]),
        .target(name: "SettingsFeature", dependencies: ["WatchSync", "WatchUI", "DesignSystem", "DocumentationFeature"]),
        .target(name: "WatchUI", dependencies: ["WatchSync", "DesignSystem"]),
        // Renders the component gallery to PNG on macOS (no simulator needed).
        .executableTarget(name: "DesignGallery", dependencies: ["DesignSystem"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain", "MockAPI"]),
        .testTarget(name: "CalendarFeatureTests", dependencies: ["CalendarFeature", "Domain"]),
        .testTarget(name: "DocumentationFeatureTests", dependencies: ["DocumentationFeature", "Domain", "MockAPI"]),
        .testTarget(name: "WatchSyncTests", dependencies: ["WatchSync", "Domain"]),
        .testTarget(name: "LiveAPITests", dependencies: ["LiveAPI", "Domain"], resources: [.copy("Fixtures")]),
    ]
)
