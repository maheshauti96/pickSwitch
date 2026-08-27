import AppKit
import Carbon.HIToolbox
import Foundation

/// The secondary keyboard trigger (Requirement 6).
///
/// Uses Carbon's `RegisterEventHotKey` rather than a `keyDown` event tap for one
/// decisive reason: it works without Input Monitoring or Accessibility. That is
/// exactly the situation it exists to cover — the user whose mouse buttons are taken
/// by another tool, or who has not finished granting permissions
/// (Requirement 10.9). Carbon is old but this specific API is neither deprecated nor
/// replaced; `NSEvent.addGlobalMonitorForEvents` would reintroduce the permission
/// dependency, and SwiftUI's `keyboardShortcut` only works when the app is frontmost,
/// which a menu-bar agent never is.
///
/// ## The silent-failure trap
///
/// `RegisterEventHotKey` returns `noErr` even when another process already owns the
/// combination — it just never delivers the keystroke. So "registered successfully"
/// proves nothing, and a fixed shortcut leaves the user with no recourse. Hence
/// `register(shortcut:)` takes the combination from settings, and `didFire` is logged
/// so an unresponsive shortcut can be distinguished from an unresponsive handler.
final class HotKeyMonitor {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var pressHandler: (() -> Void)?
    private var releaseHandler: ((TimeInterval) -> Void)?
    private var pressTimestamp: DispatchTime?
    private(set) var registeredShortcut: HotKeyShortcut?
    /// Set the first time the shortcut actually fires. If this stays false while the
    /// user insists they are pressing the keys, the combination is being swallowed
    /// upstream and they need a different one.
    private(set) var hasEverFired = false

    private static let signature: OSType = {
        // 'PKSW'
        let bytes: [UInt8] = [0x50, 0x4B, 0x53, 0x57]
        return bytes.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()
    private static let identifier: UInt32 = 1

    deinit {
        unregister()
    }

    /// Register the shortcut, handling both press and release.
    ///
    /// Release matters more than it looks. Some mice hold their extra buttons inside
    /// the mouse itself, so the press never reaches an event tap at any level and the
    /// only route to using that button is to assign it to a keyboard shortcut.
    /// Handling `kEventHotKeyReleased` as well as pressed means a button routed that
    /// way behaves exactly like a real mouse button: tap to keep the strip open, hold
    /// and release to switch.
    ///
    /// - Returns: `false` only when registration itself failed. A `true` return does
    ///   **not** guarantee the shortcut will fire; see the type comment.
    @discardableResult
    func register(
        shortcut: HotKeyShortcut,
        onPress: @escaping () -> Void,
        onRelease: @escaping (TimeInterval) -> Void
    ) -> Bool {
        unregister()
        self.pressHandler = onPress
        self.releaseHandler = onRelease

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == HotKeyMonitor.identifier else {
                    return OSStatus(eventNotHandledErr)
                }

                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)

                if kind == UInt32(kEventHotKeyReleased) {
                    let held = monitor.consumeHeldDuration()
                    DispatchQueue.main.async { monitor.releaseHandler?(held) }
                } else {
                    monitor.recordFiring()
                    DispatchQueue.main.async { monitor.pressHandler?() }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes[0],
            selfPointer,
            &eventHandler
        )

        guard installStatus == noErr else {
            Log.trigger.error("InstallEventHandler failed: \(installStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, hotKeyRef != nil else {
            Log.trigger.error("""
                RegisterEventHotKey failed for \(shortcut.displayName, privacy: .public): \
                \(registerStatus); the combination is probably already taken
                """)
            unregister()
            return false
        }

        registeredShortcut = shortcut
        hasEverFired = false
        Log.trigger.info("""
            global hotkey \(shortcut.displayName, privacy: .public) registered \
            (note: success here does not prove another app is not swallowing it)
            """)
        return true
    }

    private func recordFiring() {
        pressTimestamp = DispatchTime.now()
        if !hasEverFired {
            hasEverFired = true
            Log.trigger.info("global hotkey fired for the first time; the shortcut is reaching Vortexflow")
        } else {
            Log.trigger.debug("global hotkey fired")
        }
    }

    /// How long the shortcut was held, for the tap-versus-hold decision.
    ///
    /// Some remappings emit a press and release back to back regardless of how long
    /// the physical button was held. That reads as a tap, which is the sensible
    /// outcome: the strip stays open and the user clicks.
    private func consumeHeldDuration() -> TimeInterval {
        guard let pressTimestamp else { return 0 }
        self.pressTimestamp = nil
        let nanoseconds = DispatchTime.now().uptimeNanoseconds - pressTimestamp.uptimeNanoseconds
        return TimeInterval(nanoseconds) / 1_000_000_000
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        pressHandler = nil
        releaseHandler = nil
        pressTimestamp = nil
        registeredShortcut = nil
    }
}
