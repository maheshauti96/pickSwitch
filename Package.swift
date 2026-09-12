// swift-tools-version:6.0
import Foundation
import PackageDescription

// VortexFlow is built with SwiftPM rather than an Xcode project so that the whole
// app can be produced from the command line with only the Command Line Tools
// installed. `Scripts/build-app.sh` wraps the executable produced here into a
// proper `Vortexflow.app` bundle (Info.plist + code signature), which is required
// for the TCC permission prompts (Accessibility / Screen Recording / Input
// Monitoring) to attach to a stable bundle identity.
//
// Layout:
//   VortexflowCore  - every model, service and view. Internal access, so tests
//                     reach it with `@testable import`.
//   Vortexflow      - thin executable shell: main.swift, NSApplication bootstrap,
//                     and Sparkle. VortexflowCore does not import Sparkle.
//
// Swift 5 language mode is deliberate: the codebase talks to CGEventTap C
// callbacks, AXUIElement (an untyped CFTypeRef world) and AppKit main-thread
// classes. Swift 6 strict concurrency would require blanket unsafe opt-outs at
// every one of those boundaries without making the code safer in practice.

/// Locate the swift-testing macro plugin when the toolchain does not load it
/// automatically.
///
/// A Command Line Tools install ships `libTestingMacros.dylib` in a `testing`
/// subdirectory of the plugin folder, and the compiler only auto-loads plugins
/// sitting directly in that folder. Without this, every `@Test` fails to expand
/// with "plugin for module 'TestingMacros' not found". An Xcode toolchain resolves
/// the plugin on its own, so the flag is added only when the nested copy is present
/// and the top-level one is not — which makes this a no-op on a normal Xcode setup
/// rather than a double-load.
func testingMacroPluginSettings() -> [SwiftSetting] {
    let toolchainRoots = [
        "/Library/Developer/CommandLineTools",
        "/Applications/Xcode.app/Contents/Developer",
    ]
    let fileManager = FileManager.default

    for root in toolchainRoots {
        let pluginDirectory = "\(root)/usr/lib/swift/host/plugins"
        let autoLoaded = "\(pluginDirectory)/libTestingMacros.dylib"
        let nested = "\(pluginDirectory)/testing/libTestingMacros.dylib"

        guard fileManager.fileExists(atPath: nested) else { continue }
        guard !fileManager.fileExists(atPath: autoLoaded) else { return [] }

        return [.unsafeFlags(["-load-plugin-library", nested])]
    }
    return []
}

/// Bake rpaths for the swift-testing runtime into the test bundle.
///
/// On a Command Line Tools install, `Testing.framework` and its private
/// `lib_TestingInterop.dylib` live under `Library/Developer`, which is not on the
/// default runtime search path. `DYLD_FRAMEWORK_PATH` cannot fix it either: the
/// SwiftPM test helper is hardened, so dyld strips `DYLD_*` from its environment.
/// Linking the rpaths in is the only approach that survives that.
///
/// Skipped when the frameworks are absent, so an Xcode toolchain is unaffected.
func testingRuntimeLinkerSettings() -> [LinkerSetting] {
    let fileManager = FileManager.default
    let candidates = [
        "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
        "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
    ]
    let present = candidates.filter { fileManager.fileExists(atPath: "\($0)") }
    guard fileManager.fileExists(
        atPath: "/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"
    ) else { return [] }

    return present.map { .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", $0]) }
}

let baseSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Vortexflow",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Vortexflow", targets: ["Vortexflow"]),
        .library(name: "VortexflowCore", targets: ["VortexflowCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "VortexflowCore",
            path: "Sources/VortexflowCore",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: baseSwiftSettings
        ),
        .executableTarget(
            name: "Vortexflow",
            dependencies: [
                "VortexflowCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Vortexflow",
            swiftSettings: baseSwiftSettings,
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "VortexflowCoreTests",
            dependencies: ["VortexflowCore"],
            path: "Tests/VortexflowCoreTests",
            swiftSettings: baseSwiftSettings + testingMacroPluginSettings(),
            linkerSettings: testingRuntimeLinkerSettings()
        ),
    ]
)
