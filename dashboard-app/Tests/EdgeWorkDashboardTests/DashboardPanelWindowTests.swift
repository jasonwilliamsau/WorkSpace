import AppKit
@testable import EdgeWorkDashboard
import XCTest

@MainActor
final class DashboardPanelWindowTests: XCTestCase {
    func testBorderlessDashboardCanBecomeKeyAndMain() {
        let window = DashboardPanelWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
    }
}
