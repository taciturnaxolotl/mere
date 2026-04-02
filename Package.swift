// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mere",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MereKit", targets: ["MereKit"]),
        .library(name: "WebKitEngine", targets: ["WebKitEngine"]),
        .library(name: "ChromiumEngine", targets: ["ChromiumEngine"]),
        .library(name: "MereCore", targets: ["MereCore"]),
        .library(name: "MereUI", targets: ["MereUI"]),
    ],
    targets: [
        // Core protocols + shared models — no engine dependency
        .target(
            name: "MereKit",
            path: "Sources/MereKit"
        ),

        // WebKit implementation — depends only on MereKit + system WebKit
        .target(
            name: "WebKitEngine",
            dependencies: ["MereKit"],
            path: "Sources/WebKitEngine"
        ),

        // Chromium/CEF stub — wire in CEF.swift here when ready
        .target(
            name: "ChromiumEngine",
            dependencies: ["MereKit"],
            path: "Sources/ChromiumEngine"
            // When adding CEF:
            // dependencies: ["MereKit", .product(name: "CEF", package: "CEF.swift")],
            // and add the CEF package to `dependencies:` above
        ),

        // Engine-agnostic controllers: Tab, WindowViewModel, CookieSyncController
        .target(
            name: "MereCore",
            dependencies: ["MereKit", "WebKitEngine", "ChromiumEngine"],
            path: "Sources/MereCore"
        ),

        // SwiftUI views — depends on MereCore, not on specific engines
        .target(
            name: "MereUI",
            dependencies: ["MereCore", "MereKit"],
            path: "Sources/MereUI"
        ),

        // Tests
        .testTarget(
            name: "MereKitTests",
            dependencies: ["MereKit", "MereCore"],
            path: "Tests/BrowserKitTests"
        ),
    ]
)
