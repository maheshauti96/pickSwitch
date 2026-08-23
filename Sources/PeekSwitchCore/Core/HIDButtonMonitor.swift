import Foundation
import IOKit.hid

/// Reads mouse buttons straight from the device's HID reports.
///
/// ## Why this exists
///
/// A `CGEventTap` only sees buttons that macOS has turned into `otherMouseDown` /
/// `otherMouseUp` events. Several buttons on real mice never become one:
///
/// - The MX Master's thumb (Gesture) button reports a HID button usage that macOS does
///   not translate into a numbered mouse button, so no tap at any level sees it.
/// - Logitech Options+ can consume or rewrite buttons before they reach the event
///   stream. Observed directly: pressing the thumb button produced an event for
///   *button 2*, the wheel click, rather than a distinct number.
///
/// This is why other applications can bind that button while PeekSwitch could not, and
/// why they tend to label it something like "Aux Button" instead of giving it a mouse
/// button number — they are reading HID usages, not mouse events.
///
/// ## What it cannot do
///
/// HID monitoring is strictly passive. There is no way to consume a press here, so the
/// button also reaches whatever is under the cursor. That is acceptable precisely for
/// the buttons this class exists to reach: a button macOS does not treat as a mouse
/// button has nothing to interfere with. For buttons that *do* produce mouse events,
/// the event tap remains in charge, because it can withhold them.
///
/// Requires Input Monitoring, which PeekSwitch already requires for the event tap.
final class HIDButtonMonitor {

    /// Button index in the same space `TriggerButton` uses, i.e. the value a
    /// `CGEvent` would report. HID button usages are 1-based (1 = primary,
    /// 2 = secondary, 3 = middle), while `CGEvent` button numbers are 0-based, so the
    /// conversion is `usage - 1`.
    typealias Handler = (_ buttonNumber: Int, _ isPressed: Bool) -> Void

    private var manager: IOHIDManager?
    private var handler: Handler?
    private(set) var isRunning = false
    /// Log every incoming HID value, and widen matching to every device and usage page.
    ///
    /// Enabled with:
    ///
    ///     defaults write dev.peekswitch.PeekSwitch logAllHIDInput -bool true
    ///
    /// This exists because a button can fail to appear for reasons that are invisible
    /// from the outside: it may be reported on a vendor-specific page rather than the
    /// standard Button page, or on a separate HID interface of the same physical mouse.
    /// Logitech's HID++ protocol does exactly this. Guessing which is expensive;
    /// watching the raw stream while the user presses the button is definitive.
    ///
    /// It cannot be a command-line flag: run from a terminal, macOS attributes Input
    /// Monitoring to the terminal rather than to PeekSwitch, and the HID manager fails
    /// to open. It has to run inside the app.
    private var isVerbose = false
    /// Highest button usage seen, purely for diagnostics: it tells a user how many
    /// buttons their mouse actually exposes.
    private(set) var highestObservedButton: Int = 0

    /// Logitech's HID++ vendor usage page, as reported by an MX Master 3 over Bluetooth
    /// alongside its Mouse and Pointer collections.
    private static let logitechHIDPPUsagePage: UInt32 = 0xFF43


    deinit {
        stop()
    }

    /// - Returns: `false` if the HID manager could not be opened, which in practice
    ///   means Input Monitoring is not granted.
    @discardableResult
    func start(verbose: Bool = false, _ handler: @escaping Handler) -> Bool {
        stop()
        self.handler = handler
        self.isVerbose = verbose

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        if verbose {
            // Every device, because a button missing from the standard mouse interface
            // may be present on a vendor-specific one. Value matching stays unfiltered
            // so nothing is missed, but `logVerbose` applies a strict allow-list before
            // anything is written — keyboard pages are never recorded.
            IOHIDManagerSetDeviceMatching(manager, nil)
            IOHIDManagerSetInputValueMatchingMultiple(manager, nil)
        } else {
            // Match pointing devices only. Matching everything would also deliver
            // keyboard usages, which the event tap and the hotkey already handle.
            let criteria: [[String: Any]] = [
                [
                    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                    kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
                ],
                [
                    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                    kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer,
                ],
                // Consumer-control interfaces carry the extra buttons on some mice.
                [
                    kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                    kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl,
                ],
            ]
            IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)

            // Filter to button usages inside IOKit rather than in the callback. Without
            // this the callback also fires for every X and Y delta, which on a
            // high-polling-rate mouse means thousands of invocations per second of
            // movement — all of them discarded. Requirement 14.3 caps idle CPU at 1% of
            // a core, and a switcher has no business spending any of it on pointer
            // motion.
            //
            // Vendor pages are matched too. That is not speculative: an MX Master 3 on
            // Bluetooth reports the usage pairs 0x1/0x6, 0x1/0x2, 0x1/0x1 *and*
            // 0xff43/0x202, the last being Logitech's HID++ interface. Buttons that
            // Options+ has diverted are announced there rather than on the Button page,
            // so a filter limited to Button and Consumer can never see them.
            let valueCriteria: [[String: Any]] = [
                [kIOHIDElementUsagePageKey: kHIDPage_Button],
                [kIOHIDElementUsagePageKey: kHIDPage_Consumer],
                [kIOHIDElementUsagePageKey: Int(Self.logitechHIDPPUsagePage)],
            ]
            IOHIDManagerSetInputValueMatchingMultiple(manager, valueCriteria as CFArray)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, _, value in
                guard result == kIOReturnSuccess, let context else { return }
                let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.handle(value: value)
            },
            context
        )

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            Log.trigger.error("IOHIDManagerOpen failed (\(openResult)); raw mouse buttons unavailable")
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            self.handler = nil
            return false
        }

        self.manager = manager
        isRunning = true
        Log.trigger.info("HID button monitor started; buttons that are not mouse events are now reachable")
        return true
    }

    func stop() {
        guard let manager else {
            handler = nil
            isRunning = false
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        handler = nil
        isRunning = false
        Log.trigger.info("HID button monitor stopped")
    }

    // MARK: - Private

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = Int(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)

        if isVerbose {
            logVerbose(element: element, usagePage: usagePage, usage: usage, value: integerValue)
        }

        guard usagePage == kHIDPage_Button, usage >= 1 else { return }

        // HID usages are 1-based; CGEvent button numbers are 0-based.
        let buttonNumber = usage - 1
        highestObservedButton = max(highestObservedButton, buttonNumber)

        handler?(buttonNumber, integerValue != 0)
    }

    /// Usage pages the verbose log is permitted to record.
    ///
    /// An allow-list, not a deny-list, and that distinction matters. The first version
    /// of this diagnostic logged every page it received, which included usage page 0x07
    /// (Keyboard/Keypad) from an attached keyboard — that is every key the user typed,
    /// written into the unified log. For an application whose entire premise is that it
    /// keeps to itself, that was unacceptable, however local the log is.
    ///
    /// These pages are the only ones a mouse button can plausibly arrive on:
    ///   0x01 Generic Desktop (non-motion usages)
    ///   0x09 Button
    ///   0x0C Consumer (some mice map extra buttons to Back/Forward here)
    ///   0xFF00 and above, vendor-specific (Logitech HID++ lives here)
    ///
    /// Keyboard pages can never be logged, verbose mode or not.
    private static func isLoggableUsagePage(_ usagePage: UInt32) -> Bool {
        switch usagePage {
        case UInt32(kHIDPage_GenericDesktop),
             UInt32(kHIDPage_Button),
             UInt32(kHIDPage_Consumer):
            return true
        default:
            // Vendor-defined range.
            return usagePage >= 0xFF00
        }
    }

    /// Consumer usages that are scroll axes rather than buttons.
    ///
    /// `0x238` is AC Pan, the horizontal scroll a thumb wheel produces.
    private static let scrollUsages: Set<Int> = [0x238, 0x233, 0x234]

    /// Print button-like input only. Never keyboard input, and never pointer motion.
    private func logVerbose(
        element: IOHIDElement,
        usagePage: UInt32,
        usage: Int,
        value: CFIndex
    ) {
        guard Self.isLoggableUsagePage(usagePage) else { return }

        // Movement and wheel deltas arrive continuously and tell us nothing about which
        // button was pressed.
        if usagePage == UInt32(kHIDPage_GenericDesktop) {
            let motionUsages: Set<Int> = [
                Int(kHIDUsage_GD_X),
                Int(kHIDUsage_GD_Y),
                Int(kHIDUsage_GD_Z),
                Int(kHIDUsage_GD_Wheel),
            ]
            if motionUsages.contains(usage) { return }
        }

        // The MX Master's horizontal thumb wheel reports as Consumer AC Pan, and it does
        // so continuously: a single nudge produced 1830 log lines and buried the button
        // presses the log existed to find. Scrolling is never a trigger button, so it is
        // filtered out rather than merely tolerated.
        if usagePage == UInt32(kHIDPage_Consumer), Self.scrollUsages.contains(usage) { return }
        var product = "unknown device"
        var vendorID = 0
        var productID = 0
        if let device = IOHIDElementGetDevice(element) as IOHIDDevice? {
            if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
                product = name
            }
            vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        }

        // Presses and releases are both logged. Skipping releases hid the pairing, and
        // without pairing a single logged press is ambiguous: it could be the button being
        // hunted for, or an ordinary click that happened at the same moment.
        let phase = value == 0 ? "up  " : "down"
        let named = usagePage == UInt32(kHIDPage_Button)
            ? " (\(Self.describeButton(usage)))"
            : ""

        Log.trigger.info("""
            HID \(phase, privacy: .public) — device: \(product, privacy: .public) \
            (vendor 0x\(String(vendorID, radix: 16), privacy: .public), \
            product 0x\(String(productID, radix: 16), privacy: .public)), \
            usagePage 0x\(String(usagePage, radix: 16), privacy: .public), \
            usage 0x\(String(usage, radix: 16), privacy: .public) (\(usage, privacy: .public))\
            \(named, privacy: .public), value \(value, privacy: .public)
            """)
    }

    /// Name the well-known HID button usages, so a log line says what was pressed rather
    /// than leaving a number to be looked up.
    private static func describeButton(_ usage: Int) -> String {
        switch usage {
        case 1: return "primary / left click"
        case 2: return "secondary / right click"
        case 3: return "middle / wheel click"
        case 4: return "thumb back"
        case 5: return "thumb forward"
        default: return "extra button \(usage)"
        }
    }
}
