import Foundation
import Testing
@testable import VortexflowCore

@Suite("Authorization")
struct AuthorizationTests {

    @Test("Onboarding stays the three grants, in that order")
    func casesStayPut() {
        #expect(Authorization.allCases.map(\.self) == [
            .inputMonitoring,
            .accessibility,
            .screenRecording,
        ])
    }
}
