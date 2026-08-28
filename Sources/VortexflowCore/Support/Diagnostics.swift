import AppKit
import Foundation

/// Command-line self-check: `Vortexflow --probe`.
///
/// The three permission-dependent paths — event tap creation, window enumeration and
/// thumbnail capture — cannot be exercised until the user has granted the matching
/// authorizations in System Settings, and a menu-bar agent gives no obvious place to
/// report on them. This prints the state of each so a setup problem can be
/// distinguished from a bug without attaching a debugger.
///
/// Prints and exits; it never installs a tap or shows the overlay.
@MainActor
public enum Diagnostics {

    public static func runProbe() {
        print("Vortexflow \(MenuBarController.versionString) diagnostics")
        print(String(repeating: "-", count: 52))

        reportPermissions()
        reportWindowIDLookup()
        reportTapLocation()
        reportEnumeration()
        reportSettings()

        print(String(repeating: "-", count: 52))
        print("Grant anything missing in System Settings, then run this again.")
    }

    private static func reportPermissions() {
        let permissions = PermissionsManager()
        permissions.refresh()

        print("\nPermissions")
        for authorization in Authorization.allCases {
            let status = permissions.status(authorization)
            let mark = status.isGranted ? "yes" : "NO "
            print("  [\(mark)] \(authorization.title): \(status.displayName)")
        }

        if !permissions.allGranted {
            print("""

                  Caveat: this probe runs as a child of your terminal, and macOS
                  attributes some checks to the parent process rather than to
                  Vortexflow — Screen Recording especially. A "not granted" line here
                  may be your terminal's status, not the app's.

                  For the app's own reading:
                    log show --predicate 'subsystem == "io.vortexflow.Vortexflow"' \\
                      --last 5m --info | grep permissions
                  """)
        }
    }

    private static func reportWindowIDLookup() {
        print("\nWindow identity")
        if AXBridge.supportsDirectWindowIDLookup {
            print("  _AXUIElementGetWindow resolved: exact window matching available")
        } else {
            print("  _AXUIElementGetWindow MISSING: falling back to geometry matching,")
            print("  which can confuse windows that share a frame")
        }
    }

    /// Where in the event pipeline the trigger tap can be installed.
    ///
    /// Decides whether a remapped mouse button is reachable at all: mouse utilities
    /// typically consume extra buttons with a session-level tap, so only a HID-level tap
    /// sees them.
    private static func reportTapLocation() {
        print("\nEvent tap placement")
        let monitor = TriggerMonitor()
        defer { monitor.uninstall() }

        if monitor.install() {
            let location = monitor.activeTapLocationDescription
            print("  trigger tap installed at: \(location) level")
            if location != "HID" {
                print("  session level only: buttons consumed by mouse software may be invisible")
            }
            print("  raw HID button monitor: \(monitor.isHIDMonitorRunning ? "running" : "NOT running")")
            if monitor.isHIDMonitorRunning {
                print("  this reaches buttons macOS does not report as mouse events,")
                print("  such as the extra side or thumb buttons on many mice")
            }
        } else {
            print("  could not create an event tap; Input Monitoring is probably not granted")
            print("  (when run from a terminal this may reflect the terminal, not Vortexflow)")
        }
    }

    private static func reportEnumeration() {
        let registry = WindowRegistry()

        let apps = registry.switchableApplicationsSnapshot()
        let zOrder = registry.captureZOrder(
            regularProcessIDs: Set(apps.map(\.processIdentifier))
        )
        print("\nCGWindowList (no permission required)")
        print("  normal-layer windows anywhere: \(zOrder.liveWindowIDs.count)")
        print("  processes owning them: \(zOrder.candidatesByPID.count)")
        print("  plausible windows on other Spaces: \(zOrder.offScreenCandidates.count)")

        // Discovering a window on another Space depends on its title, and CGWindowList
        // withholds titles without Screen Recording — so a zero here usually means a
        // missing permission rather than an absence of windows.
        if zOrder.offScreenCandidates.isEmpty, zOrder.liveWindowIDs.count > zOrder.candidatesByPID.count {
            print("  none identifiable: without Screen Recording, window titles are blank,")
            print("  and a title is what separates a real window from a helper surface")
        }

        // Measure cold and warm separately. The app pre-warms its caches at launch on
        // a background queue, so the warm figure is the one a real trigger pays and
        // the one Requirement 1.2's 50 ms budget applies to. Reporting only the cold
        // number would overstate the cost of every switch after the first.
        let coldStart = DispatchTime.now()
        let entries = registry.enumerate()
        let cold = Double(DispatchTime.now().uptimeNanoseconds - coldStart.uptimeNanoseconds) / 1_000_000

        let warmStart = DispatchTime.now()
        let warmEntries = registry.enumerate()
        let warm = Double(DispatchTime.now().uptimeNanoseconds - warmStart.uptimeNanoseconds) / 1_000_000

        let mode = AXIsProcessTrusted() ? "Accessibility" : "CGWindowList fallback (no Accessibility)"
        print("\nWindow enumeration via \(mode)")
        print(String(format: "  cold: %d windows in %.1f ms", entries.count, cold))
        print(String(
            format: "  warm: %d windows in %.1f ms  %@ (budget 50 ms)",
            warmEntries.count,
            warm,
            warm <= 50 ? "PASS" : "OVER"
        ))

        if entries.isEmpty {
            print("  nothing enumerated.")
            return
        }

        let tracker = MRUTracker()
        let ordered = tracker.ordered(entries, historyDepth: SettingsStore().historyDepth)
        let resting = ordered.resting
        let minimized = resting.filter(\.isMinimized).count
        let appLevelOnly = resting.filter { $0.axElement == nil }.count

        print("  minimized among them: \(minimized)")
        print("  remembered from other Spaces: \(registry.rememberedWindowCount)")
        if appLevelOnly > 0 {
            print("  activating by application only (no Accessibility handle): \(appLevelOnly)")
        }
        // Reported whenever the two lists differ, because "why is X missing" is exactly the question
        // this probe exists to answer, and the answer is usually this line.
        if ordered.all.count != resting.count {
            print("""
                  history depth trimmed \(ordered.all.count - resting.count) window(s) from the \
                resting list; all \(ordered.all.count) remain findable by typing
                """)
        }
        print("\n  Strip contents, in order:")
        for (index, entry) in resting.enumerated() {
            let marker = entry.isMinimized ? " (minimized)" : ""
            print("    \(index + 1). \(entry.applicationName) — \(entry.displayTitle)\(marker)")
        }
        let trimmed = ordered.all.filter { candidate in
            !resting.contains { $0.windowID == candidate.windowID }
        }
        if !trimmed.isEmpty {
            print("\n  Searchable but not shown:")
            for entry in trimmed {
                print("    · \(entry.applicationName) — \(entry.displayTitle)")
            }
        }
    }

    private static func reportSettings() {
        let settings = SettingsStore()
        print("\nSettings")
        print("  trigger button: \(settings.triggerButton.displayName)")
        print("  activation: \(settings.activationMode.displayName)")
        print("  windows shown: \(settings.historyDepth)")
        print("  keyboard shortcut: \(settings.hotKeyShortcut.displayName)")
        // Worth reporting: "my previews are blank" has entirely different causes in the two
        // view modes, and Icon View not needing Screen Recording makes the permission report
        // above read differently. Same for the arrangement, which decides the panel's shape.
        print("  each window shows: \(settings.overlayViewMode.displayName)")
        print("  arrangement: \(settings.overlayLayoutStyle.displayName)")
        // Worth reporting because it is invisible until you try to screenshot and get a desktop
        // with a hole in it.
        print("  in screenshots: \(settings.includeOverlayInScreenshots ? "yes" : "no, hidden from capture")")

        if let warning = settings.triggerButton.conflictWarning {
            print("\n  Note on the current trigger button:")
            print("    \(warning)")
        }
    }
}
