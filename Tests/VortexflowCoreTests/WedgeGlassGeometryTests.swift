import CoreGraphics
import Testing
@testable import VortexflowCore

@Suite("Localized glass geometry")
struct WedgeGlassGeometryTests {
    @Test("Local glass bounds preserve the original wedge hit shape")
    func localShapeMatchesGlobalShape() {
        let shape = WedgeShape(centre: CGPoint(x: 460, y: 410), startAngle: 0.12,
            endAngle: 0.82, innerRadius: 115, outerRadius: 225, cornerRadius: 9)
        let bounds = shape.materialBounds
        let local = shape.localized(to: bounds)
        let worldPath = shape.path(in: .zero)
        let localPath = local.path(in: CGRect(origin: .zero, size: bounds.size))
        #expect(bounds.width < 460)
        #expect(bounds.height < 410)
        for x in stride(from: 0.0, through: 800, by: 13) {
            for y in stride(from: 0.0, through: 800, by: 13) {
                let point = CGPoint(x: x, y: y)
                let shifted = CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
                #expect(worldPath.contains(point) == localPath.contains(shifted))
            }
        }
    }
}
