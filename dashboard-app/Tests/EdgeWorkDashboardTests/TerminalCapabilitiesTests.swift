@testable import EdgeWorkDashboard
import XCTest

final class TerminalCapabilitiesTests: XCTestCase {
    func testITermSupportsEveryConfiguredLayout() {
        XCTAssertEqual(ITerm2Provider().capabilities.layouts, TerminalLayout.allCases)
    }

    func testMacOSTerminalOnlyOffersReliableWindowLayout() {
        let capabilities = MacOSTerminalProvider().capabilities

        XCTAssertEqual(capabilities.layouts, [.windows])
        XCTAssertTrue(capabilities.supports(.windows))
        XCTAssertFalse(capabilities.supports(.splitVertically))
        XCTAssertFalse(capabilities.supports(.tabs))
    }
}
