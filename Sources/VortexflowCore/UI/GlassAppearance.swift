import SwiftUI

/// Test/preview-only override. Normal app views inherit the system preference.
private struct OverlayTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var overlayReduceTransparencyOverride: Bool? {
        get { self[OverlayTransparencyOverrideKey.self] }
        set { self[OverlayTransparencyOverrideKey.self] = newValue }
    }
}

private struct HubMotionTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    /// Deterministic frames for pixel tests; nil in the running app.
    var hubMotionTime: TimeInterval? {
        get { self[HubMotionTimeKey.self] }
        set { self[HubMotionTimeKey.self] = newValue }
    }
}

/// A periodic clock also runs in a visible, non-key agent panel. The animation
/// schedule can throttle with app activity; explicit visibility stops idle work.
struct HubMotionView<Content: View>: View {
    let animated: Bool
    @ViewBuilder let content: (HubMotion.Sample) -> Content
    @Environment(\.hubMotionTime) private var fixedTime

    var body: some View {
        if !animated {
            content(.resting)
        } else if let fixedTime {
            content(HubMotion.sample(at: fixedTime))
        } else {
            TimelineView(.periodic(from: .now, by: HubMotion.frameInterval)) { timeline in
                content(HubMotion.sample(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}
