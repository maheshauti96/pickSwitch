import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol TriggerMonitorDelegate: AnyObject {
    func triggerButtonPressed()
    /// - Parameter duration: how long the button was held. Drives the tap-versus-hold
    ///   decision in `ActivationMode.automatic`. Measured at the event tap rather than
    ///   by the delegate, because that is the only place with both timestamps.
    func triggerButtonReleased(heldFor duration: TimeInterval)
    /// A primary-button press observed by the overlay's HID-level event tap. The point
    /// uses AppKit's global screen coordinates so the controller can share its normal
    /// card hit-testing path.
    func leftMousePressed(atScreenPoint point: CGPoint)
    func scrollReceived(delta: Double)
    func escapePressed()
    /// The registered shortcut pressed again while the overlay is up. Distinct from
    /// `escapePressed()`, which backs out of a search first.
    func keyboardShortcutPressed()
    func confirmPressed()
    /// An arrow key pressed while the overlay is up, for moving the selection without the mouse.
    func arrowPressed(_ direction: ArrowDirection)
    /// Printable characters typed while the overlay is up, for the search field.
    func searchCharactersTyped(_ characters: String)
    /// Backspace or forward delete, to shorten the search query.
    func searchBackspacePressed()
    /// Requirement 5.13: repeated tap disables mean the trigger is unreliable.
    func eventTapBecameUnstable(_ unstable: Bool)
    /// A button was pressed while the monitor was in capture mode, so Settings can
    /// assign whatever button the user actually has rather than a guessed number.
    func buttonCaptured(number: Int)
}

/// Owns the CGEventTaps that turn a raw mouse button into "show the switcher"
/// (Requirement 5).
///
/// ## Why two taps rather than one
///
/// Requirement 5.2 wants only `otherMouseDown`/`otherMouseUp` observed while the
/// overlay is hidden, and 5.6 wants scroll and key events added while it is visible.
/// A tap's event mask is fixed at creation, so honouring both literally would mean
/// destroying and recreating a tap on every presentation — directly on the latency
/// path that Requirement 14.1 caps at 150 ms, and a reliable source of dropped
/// events.
///
/// Instead both taps are created once at launch:
///
/// - `buttonTap` (`otherMouseDown | otherMouseUp`) stays enabled for the process
///   lifetime.
/// - `overlayTap` (`scrollWheel | keyDown`) is created disabled and toggled with
///   `CGEvent.tapEnable`. A disabled tap is skipped by the window server entirely,
///   so while the overlay is hidden, scroll and key events genuinely do bypass it —
///   which is what 5.2 is protecting. Toggling is a single call with no allocation,
///   so it adds nothing measurable to presentation time.
///
/// ## Pass-through discipline
///
/// The callback consumes an event only when it is one PeekSwitch acts on
/// (Requirement 5.4, 5.7). Every other event is returned untouched
/// (Requirement 5.3). Getting this wrong would break middle-click-to-open-in-new-tab
/// system-wide, so the button-number comparison is the first thing the callback does
/// and the only reason it ever returns `nil`.
///
/// ## Callback budget
///
/// Requirement 5.11 caps each callback at 5 ms. The callback therefore does nothing
/// but read one integer field and `async` a closure onto the main queue. All
/// enumeration, capture and rendering happens after the callback has already
/// returned. Overrunning the budget is not merely slow: macOS responds by disabling
/// the tap, which is the failure mode `handleDisabled` exists to recover from.
final class TriggerMonitor {

    weak var delegate: TriggerMonitorDelegate?

    /// Read on the tap thread, written on main. `Atomic`-by-convention: it is a
    /// single word and a stale read for one event is harmless (worst case one
    /// press uses the previous button assignment).
    var triggerButton: TriggerButton = SettingsStore.defaultTriggerButton

    private var buttonTap: CFMachPort?
    private var buttonSource: CFRunLoopSource?
    private var overlayTap: CFMachPort?
    private var overlaySource: CFRunLoopSource?

    /// Supplementary source for buttons the event tap never sees. See
    /// `HIDButtonMonitor` for why that set is not empty.
    private let hidMonitor = HIDButtonMonitor()

    /// Set from `SettingsStore` by the owner before `install()`.
    var logsAllHIDInput = false

    var isHIDMonitorRunning: Bool { hidMonitor.isRunning }
    var highestObservedButton: Int { hidMonitor.highestObservedButton }

    private var isOverlayTapEnabled = false
    /// AppKit screen-space frame of the visible panel. The event-tap callback runs on
    /// the same main run loop that updates this value, so reading it is serialized.
    /// It lets the tap consume card clicks while allowing outside clicks to pass to
    /// the application underneath.
    private var overlayClickRegion: CGRect?
    /// Guards against a synthetic or missed `up` leaving the overlay stuck open.
    private var isTriggerHeld = false
    /// When the current press started, for the tap-versus-hold decision.
    private var pressTimestamp: DispatchTime?

    /// While true, the next button press is reported through
    /// `TriggerMonitorDelegate.buttonCaptured(number:)` instead of opening the overlay.
    ///
    /// This exists because a fixed list of button numbers cannot cover real mice: extra
    /// buttons report numbers no preset list would guess. Letting the user press the
    /// button they want removes the guesswork, and also makes it obvious when a button
    /// never arrives at all because the mouse is keeping it to itself.
    var isCapturingButton = false

    // Requirement 5.13: three disables inside 60 s raises the warning.
    private var disableTimestamps: [Date] = []
    private static let disableWindow: TimeInterval = 60
    private static let disableThreshold = 3

    /// Beyond this many disables in the window, stop re-arming immediately and back
    /// off, so a tap macOS refuses to keep alive cannot spin the CPU.
    private static let reArmGiveUpThreshold = 12
    private static let backoffDuration: TimeInterval = 5
    private var backoffUntil: Date?

    /// The registered global shortcut, so its key is never mistaken for typing.
    ///
    /// Without this the shortcut cannot close the overlay it opened: the tap sits ahead of the
    /// hotkey in the pipeline, so consuming the keystroke as a search character means the hotkey
    /// never fires. See `KeyResponse`.
    var keyboardShortcut: HotKeyShortcut?

    private(set) var isInstalled = false
    /// Which pipeline position the button tap ended up at. Surfaced in diagnostics
    /// because it decides whether remapped mouse buttons are reachable.
    private(set) var activeTapLocation: CGEventTapLocation?

    var activeTapLocationDescription: String {
        guard let activeTapLocation else { return "none" }
        return Self.describe(activeTapLocation)
    }

    deinit {
        // deinit cannot hop to the main actor; tear down the CF objects directly.
        // Safe because these are plain CF types with no actor affinity.
        if let buttonSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), buttonSource, .commonModes) }
        if let overlaySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), overlaySource, .commonModes) }
        if let buttonTap { CGEvent.tapEnable(tap: buttonTap, enable: false) }
        if let overlayTap { CGEvent.tapEnable(tap: overlayTap, enable: false) }
    }

    // MARK: - Lifecycle

    /// - Returns: `false` when the tap could not be created, which in practice means
    ///   Input Monitoring is not granted (Requirement 5.14).
    @discardableResult
    func install() -> Bool {
        guard !isInstalled else { return true }

        let buttonMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        guard let buttonTap = makeTap(mask: buttonMask, kind: .button) else {
            Log.trigger.error("failed to create mouse button event tap; Input Monitoring likely denied")
            return false
        }
        self.buttonTap = buttonTap
        buttonSource = addToRunLoop(buttonTap)
        CGEvent.tapEnable(tap: buttonTap, enable: true)

        let overlayMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        if let overlayTap = makeTap(mask: overlayMask, kind: .overlay) {
            self.overlayTap = overlayTap
            overlaySource = addToRunLoop(overlayTap)
            // Created disabled: nothing bypasses it until the overlay opens.
            CGEvent.tapEnable(tap: overlayTap, enable: false)
            isOverlayTapEnabled = false
        } else {
            Log.trigger.error("failed to create overlay event tap; scroll and Escape will be unavailable")
        }

        // Supplementary, and deliberately not fatal if it fails: the event tap alone
        // still covers every button macOS reports as a mouse event.
        hidMonitor.start(verbose: logsAllHIDInput) { [weak self] number, isPressed in
            MainActor.assumeIsolated {
                self?.handleHIDButton(number: number, isPressed: isPressed)
            }
        }
        if logsAllHIDInput {
            Log.trigger.info("verbose HID logging is on; press the button you want to identify")
        }

        isInstalled = true
        Log.trigger.info("event taps installed")
        return true
    }

    /// A button press seen in the raw HID stream.
    ///
    /// Both this and the event tap can report the same physical button, so the two are
    /// deduplicated through `isTriggerHeld`: whichever source arrives first flips the
    /// flag, and the second sees it already set and drops its copy. That needs no timing
    /// window and cannot double-fire, because the flag *is* the state machine.
    @MainActor
    private func handleHIDButton(number: Int, isPressed: Bool) {
        // The primary and secondary buttons come through here too. They can never be a
        // trigger, and swallowing them during capture would stop the user clicking
        // Cancel in Settings.
        guard number >= TriggerButton.minimumNumber else { return }

        if isCapturingButton {
            guard isPressed else { return }
            isCapturingButton = false
            isTriggerHeld = false
            delegate?.buttonCaptured(number: number)
            return
        }

        guard number == triggerButton.number else { return }

        if isPressed {
            guard !isTriggerHeld else { return }
            isTriggerHeld = true
            pressTimestamp = DispatchTime.now()
            delegate?.triggerButtonPressed()
        } else {
            guard isTriggerHeld else { return }
            isTriggerHeld = false
            let held = elapsedSincePress()
            pressTimestamp = nil
            delegate?.triggerButtonReleased(heldFor: held)
        }
    }

    func uninstall() {
        hidMonitor.stop()
        if let buttonSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), buttonSource, .commonModes)
        }
        if let overlaySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), overlaySource, .commonModes)
        }
        if let buttonTap { CGEvent.tapEnable(tap: buttonTap, enable: false) }
        if let overlayTap { CGEvent.tapEnable(tap: overlayTap, enable: false) }
        buttonTap = nil
        overlayTap = nil
        buttonSource = nil
        overlaySource = nil
        isInstalled = false
        isOverlayTapEnabled = false
        Log.trigger.info("event taps removed")
    }

    /// Requirement 5.6 / 5.8.
    func setOverlayTapEnabled(_ enabled: Bool, clickRegion: CGRect? = nil) {
        // Publish the region before enabling and clear it only after disabling so the
        // callback never consumes a click without also dispatching it to the overlay.
        if enabled {
            overlayClickRegion = clickRegion
        }

        if let overlayTap, enabled != isOverlayTapEnabled {
            CGEvent.tapEnable(tap: overlayTap, enable: enabled)
            isOverlayTapEnabled = enabled
        }

        if !enabled {
            overlayClickRegion = nil
        }
    }

    /// Called when the overlay closes for a reason other than the button coming up
    /// (Escape, click-outside, display change) so a later `up` is not misread as a
    /// fresh gesture.
    func clearHeldState() {
        isTriggerHeld = false
        pressTimestamp = nil
    }

    private func elapsedSincePress() -> TimeInterval {
        guard let pressTimestamp else { return 0 }
        let nanoseconds = DispatchTime.now().uptimeNanoseconds - pressTimestamp.uptimeNanoseconds
        return TimeInterval(nanoseconds) / 1_000_000_000
    }

    // MARK: - Tap plumbing

    /// Which of the two taps a callback is speaking for.
    ///
    /// This has to be baked into the callback rather than looked up, because macOS
    /// reports a tap being disabled by handing the *tap's own callback* a
    /// `tapDisabledBy…` event, with nothing in the event identifying which tap it is.
    /// With one shared callback the monitor could not tell "the OS disabled my button
    /// tap" from "I just disabled my own overlay tap", and re-arming blindly turned
    /// the second case into an infinite loop.
    private enum TapKind {
        case button
        case overlay
    }

    // Two distinct C callbacks. Neither closure captures anything — they reference a
    // static method and a literal — so both convert to `@convention(c)`.
    private static let buttonTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        TriggerMonitor.handle(proxy: proxy, type: type, event: event, refcon: refcon, kind: .button)
    }

    private static let overlayTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        TriggerMonitor.handle(proxy: proxy, type: type, event: event, refcon: refcon, kind: .overlay)
    }

    /// Tap locations to try, earliest in the event pipeline first.
    ///
    /// `.cghidEventTap` is the crucial one. Mouse-remapping utilities install their own
    /// event tap at the *session* level and consume the extra mouse buttons there. A tap
    /// created at `.cgSessionEventTap` sits alongside those consumers and simply never
    /// sees the button, which is exactly why a side button could appear undetectable here
    /// while other applications used it perfectly well. `.cghidEventTap` sits ahead of
    /// session-level taps, so the button arrives before anything else can swallow it.
    ///
    /// Creating a HID-level tap needs Input Monitoring, which PeekSwitch already
    /// requires. Session level is kept as a fallback for the case where the HID tap
    /// cannot be created, since a session tap is still better than no trigger at all.
    private static let tapLocations: [CGEventTapLocation] = [
        .cghidEventTap,
        .cgSessionEventTap,
    ]

    private static func describe(_ location: CGEventTapLocation) -> String {
        location == .cghidEventTap ? "HID" : "session"
    }

    private func makeTap(mask: CGEventMask, kind: TapKind) -> CFMachPort? {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        for location in Self.tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                // `.defaultTap` (not `.listenOnly`) because the trigger button must be
                // withheld from the app underneath the cursor.
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: kind == .button ? Self.buttonTapCallback : Self.overlayTapCallback,
                userInfo: userInfo
            ) {
                if kind == .button {
                    activeTapLocation = location
                    Log.trigger.info("button event tap created at \(Self.describe(location), privacy: .public) level")
                }
                return tap
            }
        }
        return nil
    }

    private func addToRunLoop(_ tap: CFMachPort) -> CFRunLoopSource? {
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return nil
        }
        // `.commonModes` so the tap keeps firing while a menu is tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return source
    }

    /// The C callback. Runs on the run loop the tap was added to (main). Must stay
    /// under 5 ms — see the class comment.
    private static func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?,
        kind: TapKind
    ) -> Unmanaged<CGEvent>? {
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<TriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()

        // Requirement 5.12: macOS hands the tap back disabled instead of an event.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.handleDisabled(reason: type, kind: kind)
            return nil
        }

        switch type {
        case .leftMouseDown:
            // AppKit does not reliably deliver primary clicks to a never-key,
            // nonactivating panel. Observe the click at the same HID-level tap that
            // already handles scrolling and keyboard confirmation, then route it to
            // the controller's normal card hit test. Consume only clicks geometrically
            // inside the panel; outside clicks still reach the application underneath.
            let screenPoint = NSEvent.mouseLocation
            let isInsideOverlay = monitor.overlayClickRegion?.contains(screenPoint) == true
            monitor.dispatch { $0.leftMousePressed(atScreenPoint: screenPoint) }
            return isInsideOverlay ? nil : Unmanaged.passUnretained(event)

        case .otherMouseDown, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)

            // The HID stream and the event stream can disagree, and knowing which layer a
            // button reaches is the whole diagnosis: a button present here but absent from
            // HID has been synthesised by mouse software, and one absent from both has been
            // consumed in the device or its driver.
            if monitor.logsAllHIDInput {
                Log.trigger.info("""
                    CGEvent \(type == .otherMouseDown ? "down" : "up  ", privacy: .public) \
                    — mouse button \(button, privacy: .public)
                    """)
            }

            // Capture mode takes precedence: report whichever button was pressed and
            // consume it so it does not also reach the app underneath.
            if monitor.isCapturingButton {
                if type == .otherMouseDown {
                    monitor.isCapturingButton = false
                    monitor.isTriggerHeld = false
                    let number = Int(button)
                    monitor.dispatch { $0.buttonCaptured(number: number) }
                }
                return nil
            }

            // Requirement 5.3: anything that is not the trigger passes straight
            // through, unmodified.
            guard button == monitor.triggerButton.buttonNumber else {
                return Unmanaged.passUnretained(event)
            }
            if type == .otherMouseDown {
                // Same dedup as the HID path, and it has to be here too. The raw HID
                // monitor reports the identical physical press, and whichever source
                // arrives second must drop its copy. Without this guard the second copy
                // reached the delegate, and because the first had already committed and
                // dismissed the overlay, the duplicate press reopened it — the strip
                // appeared never to close.
                guard !monitor.isTriggerHeld else { return nil }
                monitor.isTriggerHeld = true
                monitor.pressTimestamp = DispatchTime.now()
                monitor.dispatch { $0.triggerButtonPressed() }
            } else {
                guard monitor.isTriggerHeld else {
                    // An `up` with no matching `down` (the down happened before
                    // launch, or was consumed elsewhere). Swallow it and stay quiet.
                    return nil
                }
                monitor.isTriggerHeld = false
                let held = monitor.elapsedSincePress()
                monitor.pressTimestamp = nil
                monitor.dispatch { $0.triggerButtonReleased(heldFor: held) }
            }
            // Requirement 5.4.
            return nil

        case .scrollWheel:
            // Requirement 5.7. Reached only while the overlay tap is enabled.
            let delta = Self.scrollDelta(from: event)
            if delta != 0 {
                monitor.dispatch { $0.scrollReceived(delta: delta) }
            }
            return nil

        case .keyDown:
            // Decided by `KeyResponse` rather than here: a C callback is the worst place in the app
            // to keep branching logic, and the branch that was here shipped a defect no test could
            // have reached.
            switch KeyResponse.forKeyDown(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                // Queried from the keyboard rather than taken from `event.flags`. At
                // `.cghidEventTap` the event's own flags are unreliable — see `KeyResponse` — and
                // getting this wrong is what made a space untypeable under an ⌥Space shortcut.
                activeModifiers: CGEventSource.flagsState(.combinedSessionState),
                characters: Self.characters(from: event),
                shortcutKeyCode: monitor.keyboardShortcut.map { Int64($0.keyCode) },
                shortcutModifiers: monitor.keyboardShortcut?.eventFlags ?? []
            ) {
            case .dismiss:
                monitor.dispatch { $0.escapePressed() }
                return nil
            case .triggerShortcut:
                // Consumed, which is the point: the Carbon hotkey behind this would otherwise
                // receive the same keystroke and act on it twice.
                monitor.dispatch { $0.keyboardShortcutPressed() }
                return nil
            case .confirm:
                monitor.dispatch { $0.confirmPressed() }
                return nil
            case .deleteSearchCharacter:
                monitor.dispatch { $0.searchBackspacePressed() }
                return nil
            case .moveSelection(let direction):
                // Consumed, like a typed character. The overlay is in front and the arrow is
                // steering it; letting the same press also reach the window underneath would
                // scroll the user's document while they were choosing which window to go to.
                monitor.dispatch { $0.arrowPressed(direction) }
                return nil
            case .typeIntoSearch(let characters):
                // Consumed rather than passed through. The overlay is visibly in front and the
                // keystroke is going into its search, so letting it also reach the application
                // underneath would type into the user's document.
                monitor.dispatch { $0.searchCharactersTyped(characters) }
                return nil
            case .passThrough:
                return Unmanaged.passUnretained(event)
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// The characters a key event would produce, honouring the active keyboard layout.
    ///
    /// Read through `CGEvent` rather than by mapping key codes, so a non-US layout types
    /// what the user expects.
    private static func characters(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }

    /// Prefer the pixel-precision delta, which is what a trackpad and a free-spinning
    /// wheel report. Notched wheels report only line deltas, so those are scaled into
    /// comparable units.
    private static func scrollDelta(from event: CGEvent) -> Double {
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if pointDelta != 0 { return -pointDelta }
        let lineDelta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        if lineDelta != 0 { return -lineDelta * 10 }

        // Horizontal wheels, where a mouse has one, report on axis 2.
        let horizontalPoint = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if horizontalPoint != 0 { return horizontalPoint }
        let horizontalLine = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        if horizontalLine != 0 { return horizontalLine * 10 }
        return 0
    }

    /// Hop to the main actor so delegate work never happens inside the tap callback.
    private func dispatch(_ body: @escaping @MainActor (TriggerMonitorDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let delegate = self?.delegate else { return }
                body(delegate)
            }
        }
    }

    // MARK: - Re-arm

    /// Requirement 5.12: put the same tap back. Re-enabling is immediate; the
    /// requirement's 1 s is an upper bound, not a delay to spend.
    ///
    /// Two rules keep this from turning into a feedback loop:
    ///
    /// 1. **Only the tap that was disabled is touched.** Re-applying state to the
    ///    *other* tap is what created the original loop: disabling the overlay tap
    ///    produced a disable event, which was answered by disabling it again.
    /// 2. **A disable we asked for is not a fault.** The overlay tap is deliberately
    ///    disabled every time the overlay closes, and macOS reports that the same way
    ///    it reports a real fault. If the tap is not supposed to be on, its disable
    ///    notification is simply acknowledged and dropped.
    private func handleDisabled(reason: CGEventType, kind: TapKind) {
        switch kind {
        case .button:
            // This tap should be on for the whole process lifetime, so any disable is
            // genuinely unexpected.
            guard let buttonTap else { return }
            recordUnexpectedDisable(reason: reason, tap: "button")
            guard shouldReArmNow else { return }
            CGEvent.tapEnable(tap: buttonTap, enable: true)

        case .overlay:
            guard let overlayTap else { return }
            guard isOverlayTapEnabled else {
                // Self-inflicted and expected: the overlay just closed. Do nothing.
                return
            }
            recordUnexpectedDisable(reason: reason, tap: "overlay")
            guard shouldReArmNow else { return }
            CGEvent.tapEnable(tap: overlayTap, enable: true)
        }
    }

    private func recordUnexpectedDisable(reason: CGEventType, tap: String) {
        let cause = reason == .tapDisabledByTimeout ? "timeout" : "user input"
        Log.trigger.warning("\(tap, privacy: .public) event tap disabled (\(cause, privacy: .public)); re-arming")

        let now = Date()
        disableTimestamps.append(now)
        disableTimestamps.removeAll { now.timeIntervalSince($0) > Self.disableWindow }

        // Requirement 5.13.
        let unstable = disableTimestamps.count >= Self.disableThreshold
        dispatch { $0.eventTapBecameUnstable(unstable) }
    }

    /// Circuit breaker. If macOS is disabling a tap faster than it can be re-armed,
    /// retrying in a tight loop burns a core and floods the log without ever
    /// recovering. Back off instead, and let the menu bar warning explain why the
    /// trigger has stopped responding.
    private var shouldReArmNow: Bool {
        guard disableTimestamps.count >= Self.reArmGiveUpThreshold else { return true }

        if let backoffUntil, Date() < backoffUntil {
            return false
        }
        if backoffUntil == nil {
            Log.trigger.error("event tap disabled repeatedly; backing off for \(Self.backoffDuration, format: .fixed(precision: 0)) s")
            backoffUntil = Date().addingTimeInterval(Self.backoffDuration)
            return false
        }
        // Backoff elapsed: clear the history and allow one more attempt.
        backoffUntil = nil
        disableTimestamps.removeAll()
        return true
    }
}
