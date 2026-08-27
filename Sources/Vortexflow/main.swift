import AppKit
import VortexflowCore

// Manual NSApplication bootstrap rather than `@main` on a SwiftUI `App` type.
//
// Vortexflow is a menu-bar agent whose main surface is a non-activating overlay
// panel. SwiftUI's `App` lifecycle insists on owning at least one scene and manages
// window activation in ways that fight both of those. AppKit's lifecycle gives
// direct control over the activation policy, the status item and the panel; the
// SwiftUI views are hosted inside it with NSHostingView.
//
// Top-level code in main.swift runs on the main thread but is not inferred as
// main-actor isolated, so the setup is wrapped in `assumeIsolated` rather than
// scattering nonisolated escapes across the AppKit types.
MainActor.assumeIsolated {
    // `--probe` reports permission state and enumeration results, then exits without
    // installing an event tap or showing any UI. A menu-bar agent has nowhere good to
    // surface that, and it is the fastest way to tell a setup problem from a bug.
    if CommandLine.arguments.contains("--probe") {
        Diagnostics.runProbe()
        exit(0)
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // Requirement 11.1: no Dock icon, absent from Cmd-Tab. Also set via LSUIElement
    // in Info.plist so the bundled app behaves this way from the instant it launches.
    application.setActivationPolicy(.accessory)

    // NSApplication holds its delegate weakly, so this scope has to keep it alive.
    withExtendedLifetime(delegate) {
        application.run()
    }
}
