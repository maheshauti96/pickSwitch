import CoreGraphics
import Foundation

/// The mouse button that opens the overlay (Requirement 12.2).
///
/// Originally a three-case enum, now an arbitrary button number. The fixed list was
/// wrong in practice: plenty of mice put buttons outside the middle/back/forward trio
/// and report numbers a closed set would never include, which made those buttons
/// unusable. Settings pairs this with a capture control that reads whatever
/// button the user actually presses, which beats asking them to guess a number.
///
/// `number` is the `buttonNumber` macOS reports on `otherMouseDown` / `otherMouseUp`.
/// Button 0 and 1 are the left and right buttons and are deliberately not accepted:
/// swallowing either would break normal clicking system-wide.
struct TriggerButton: Equatable, Hashable, Codable, Sendable {

    /// Left (0) and right (1) are excluded on purpose.
    static let minimumNumber = 2
    /// `NSEvent.buttonNumber` is bounded well below this in practice; the cap just
    /// keeps a corrupt preference from producing nonsense.
    static let maximumNumber = 31

    let number: Int

    /// Fails for the left and right buttons, and for out-of-range values.
    init?(number: Int) {
        guard (Self.minimumNumber...Self.maximumNumber).contains(number) else { return nil }
        self.number = number
    }

    /// Non-failable variant for the known-good constants below.
    private init(unchecked number: Int) {
        self.number = number
    }

    // MARK: - Well-known buttons

    /// Wheel click.
    static let middle = TriggerButton(unchecked: 2)
    /// The rear side button found on most mice with more than three buttons, usually
    /// labelled "Back".
    static let thumbBack = TriggerButton(unchecked: 3)
    /// The front side button, usually labelled "Forward".
    static let thumbForward = TriggerButton(unchecked: 4)

    /// Offered in the Settings picker. Any other button reaches the setting through
    /// the capture control.
    static let presets: [TriggerButton] = [.middle, .thumbBack, .thumbForward]

    // MARK: - Storage

    /// Persisted representation. Matches the old enum's raw values for the three
    /// original cases, so existing preferences keep working.
    var rawValue: Int { number }

    init?(rawValue: Int) {
        self.init(number: rawValue)
    }

    /// What the event tap compares against.
    var buttonNumber: Int64 { Int64(number) }

    static func from(buttonNumber: Int64) -> TriggerButton? {
        TriggerButton(number: Int(buttonNumber))
    }

    // MARK: - Presentation

    var displayName: String {
        switch number {
        case 2: return "Middle Button (wheel click)"
        case 3: return "Thumb Back (button 3)"
        case 4: return "Thumb Forward (button 4)"
        default: return "Button \(number)"
        }
    }

    var shortName: String {
        switch number {
        case 2: return "Middle"
        case 3: return "Thumb Back"
        case 4: return "Thumb Forward"
        default: return "Button \(number)"
        }
    }

    /// True for buttons the system or apps commonly rely on, so Settings can warn
    /// that claiming them has a cost elsewhere.
    var hasCommonConflict: Bool { number == 2 }

    var conflictWarning: String? {
        guard hasCommonConflict else { return nil }
        return "Vortexflow has to consume this button, so middle-click to open a link in a new tab will stop working in browsers. A thumb button avoids that."
    }
}
