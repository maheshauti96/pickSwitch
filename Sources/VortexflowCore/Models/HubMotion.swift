import Foundation
import SwiftUI

/// Small, bounded motion around a fixed hit target and a stationary caption.
enum HubMotion {
    static let frameInterval: TimeInterval = 1.0 / 24.0
    static let maximumRadiusScale = 1.04

    struct Sample: Equatable {
        let energy: Double
        let phase: Double
        let radiusScale: Double
        let ripple: Double

        static let resting = Sample(energy: 0.55, phase: 0, radiusScale: 1, ripple: 0)

        func radialScale(at angle: Double) -> Double {
            radiusScale + ripple * (sin(3 * angle + phase) + 0.32 * sin(5 * angle - 2 * phase))
        }
    }

    static func shouldAnimate(isVisible: Bool, isRevealed: Bool, reduceMotion: Bool) -> Bool {
        isVisible && isRevealed && !reduceMotion
    }

    static func sample(at time: TimeInterval, animated: Bool = true) -> Sample {
        guard animated else { return .resting }
        let breath = time.truncatingRemainder(dividingBy: HubChrome.pulsePeriod) / HubChrome.pulsePeriod * 2 * .pi
        let phase = time.truncatingRemainder(dividingBy: HubChrome.sheenPeriod) / HubChrome.sheenPeriod * 2 * .pi
        let energy = 0.5 + 0.5 * sin(breath)
        return Sample(energy: energy, phase: phase,
            radiusScale: 1 + 0.008 * sin(breath), ripple: 0.018 * (0.6 + 0.4 * energy))
    }
}

/// Only the optical rim ripples. Layout, the caption and selection geometry do not.
struct LiquidHubContour: Shape {
    let motion: HubMotion.Sample

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return Path() }
        var path = Path()
        for index in 0..<180 {
            let angle = Double(index) / 180 * 2 * .pi
            let r = radius * motion.radialScale(at: angle)
            let point = CGPoint(x: rect.midX + r * cos(angle), y: rect.midY + r * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
