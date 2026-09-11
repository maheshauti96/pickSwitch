import ApplicationServices
import Foundation

/// Thin, crash-safe wrappers over the untyped AXUIElement C API.
///
/// Two things matter here:
///
/// 1. Every accessor returns an optional instead of trapping. Windows disappear
///    between enumeration and use constantly, and every AX call against a dead
///    element returns an error rather than a value.
/// 2. Messaging timeouts are set explicitly. The default AX timeout is 6 seconds;
///    a single unresponsive application would blow the 50 ms enumeration budget
///    (Requirement 1.2) and hang the overlay. Apple applies a timeout only to the
///    exact AX object passed in, so child elements returned by an attribute read are
///    configured here as well as their application object.
enum AXBridge {

    /// Ceiling for any single AX round trip.
    ///
    /// This started at 0.05 s to protect the 50 ms enumeration budget, and that was the
    /// wrong trade. AX calls are IPC round trips, and they get slow exactly when the
    /// system is busiest — which is the instant after VortexFlow activates a window,
    /// and therefore the instant before the user is most likely to reopen the switcher.
    /// A timeout that tight made every application's window query fail at once, and
    /// enumeration returned nothing, which surfaced as a "no switchable windows are
    /// open" box immediately after switching.
    ///
    /// A slow switcher is a much smaller problem than a switcher that claims there is
    /// nothing to switch to. Enumeration runs the applications in parallel and stops
    /// waiting at its own shorter presentation deadline. This per-message ceiling bounds
    /// how long a worker can remain inside AX after that deadline.
    static let messagingTimeout: Float = 0.25

    static func applyMessagingTimeout(_ element: AXUIElement, seconds: Float = messagingTimeout) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    // MARK: - Attribute reads

    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyAttribute(element, attribute) as? Bool
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let elements = copyAttribute(element, attribute) as? [AXUIElement] else {
            return nil
        }
        // `AXUIElementSetMessagingTimeout` is object-specific. A timeout set on the
        // application does not carry into the window, group or button objects it returns.
        for child in elements {
            applyMessagingTimeout(child)
        }
        return elements
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let child = value as! AXUIElement
        applyMessagingTimeout(child)
        return child
    }

    /// A conditional cast from `CFTypeRef` to `AXValue` always succeeds at compile
    /// time, so the real type has to be checked with `CFGetTypeID` before the
    /// unconditional bridge.
    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXValue)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var result = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &result) else { return nil }
        return result
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &result) else { return nil }
        return result
    }

    // MARK: - Attribute writes / actions

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) == .success
    }

    @discardableResult
    static func setPoint(_ element: AXUIElement, _ attribute: String, _ value: CGPoint) -> Bool {
        var point = value
        guard let wrapped = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, wrapped) == .success
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ attribute: String, _ value: CGSize) -> Bool {
        var size = value
        guard let wrapped = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, wrapped) == .success
    }

    /// Move and resize in one call, position first.
    ///
    /// The order is not incidental. A window is resized within whatever screen it currently occupies,
    /// so growing it before moving it can have the window manager clamp the new size to the *old*
    /// screen — which is how a window tiled to the half of a smaller display ends up the wrong size.
    /// Setting the size again afterwards costs one more round trip and settles windows that clamped
    /// their width to a minimum before the move.
    ///
    /// Returns whether both attributes were accepted. Some windows are simply not resizable, and
    /// reporting that honestly is better than a silent no-op.
    @discardableResult
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        let moved = setPoint(element, kAXPositionAttribute as String, frame.origin)
        let sized = setSize(element, kAXSizeAttribute as String, frame.size)
        if moved { setPoint(element, kAXPositionAttribute as String, frame.origin) }
        return moved && sized
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    // MARK: - CGWindowID correlation

    /// `_AXUIElementGetWindow` is the only reliable way to map an AXUIElement to
    /// the CGWindowID that ScreenCaptureKit and CGWindowList speak in. It is not
    /// in any public header, so it is resolved at runtime rather than linked.
    ///
    /// This is the same approach alt-tab-macos and DockDoor take. The alternative
    /// (matching on title plus frame) breaks on the exact cases this app must get
    /// right: several same-titled windows of one app, and windows that share a
    /// frame because they are tiled or stacked.
    ///
    /// `windowID(for:)` falls back to `nil` if the symbol ever disappears, and the
    /// registry then falls back to geometry matching.
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindowFunction: GetWindowFunction? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            Log.registry.warning("_AXUIElementGetWindow unavailable; falling back to geometry matching")
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    static var supportsDirectWindowIDLookup: Bool { getWindowFunction != nil }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let function = getWindowFunction else { return nil }
        // Observer callbacks can hand us an element that did not pass through
        // `elements` or `element` above.
        applyMessagingTimeout(element)
        var identifier = CGWindowID(0)
        guard function(element, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }
}
