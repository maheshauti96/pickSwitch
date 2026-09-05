import CoreGraphics
import Testing
@testable import VortexflowCore

@Suite("Liquid hub motion")
struct HubMotionTests {
    @Test("Hidden and reduced-motion presentations have no animation clock")
    func clockPolicy() {
        #expect(HubMotion.shouldAnimate(isVisible: true, isRevealed: true, reduceMotion: false))
        #expect(!HubMotion.shouldAnimate(isVisible: false, isRevealed: true, reduceMotion: false))
        #expect(!HubMotion.shouldAnimate(isVisible: true, isRevealed: false, reduceMotion: false))
        #expect(!HubMotion.shouldAnimate(isVisible: true, isRevealed: true, reduceMotion: true))
        #expect(HubMotion.sample(at: 0, animated: false) == HubMotion.sample(at: 37, animated: false))
    }

    @Test("The optical rim cannot move into the caption or change hit geometry")
    func boundedContour() {
        for tick in 0..<240 {
            let motion = HubMotion.sample(at: Double(tick) / 24)
            #expect((0...1).contains(motion.energy))
            for step in 0..<72 {
                let scale = motion.radialScale(at: Double(step) / 72 * 2 * .pi)
                #expect(scale >= 0.96)
                #expect(scale <= HubMotion.maximumRadiusScale)
            }
        }
    }

    @Test("Animated frames visibly differ, while a resting contour is a circle")
    func frameVariation() {
        let frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        let a = LiquidHubContour(motion: HubMotion.sample(at: 0)).path(in: frame)
        let b = LiquidHubContour(motion: HubMotion.sample(at: 1.1)).path(in: frame)
        #expect(a != b)
        for step in 0..<72 {
            #expect(HubMotion.Sample.resting.radialScale(at: Double(step)) == 1)
        }
    }

    @Test("Traveling light has no jump at its loop seam")
    func continuousLoop() {
        let before = HubMotion.sample(at: HubChrome.sheenPeriod - 0.0001)
        let after = HubMotion.sample(at: HubChrome.sheenPeriod + 0.0001)
        for step in 0..<72 {
            let angle = Double(step) / 72 * 2 * .pi
            #expect(abs(before.radialScale(at: angle) - after.radialScale(at: angle)) < 0.001)
        }
    }
}
