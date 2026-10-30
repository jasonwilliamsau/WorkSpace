@testable import EdgeWorkDashboard
import XCTest

final class SystemMetricsProviderTests: XCTestCase {
    func testFormatsUptimeAtUsefulGranularity() {
        XCTAssertEqual(SystemMetricsProvider.formattedUptime(45), "Up 0m")
        XCTAssertEqual(SystemMetricsProvider.formattedUptime(5_400), "Up 1h 30m")
        XCTAssertEqual(SystemMetricsProvider.formattedUptime(183_600), "Up 2d 3h")
    }
}
