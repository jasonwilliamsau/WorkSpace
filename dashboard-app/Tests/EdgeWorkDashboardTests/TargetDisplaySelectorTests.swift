import AppKit
import CoreGraphics
@testable import EdgeWorkDashboard
import XCTest

final class TargetDisplaySelectorTests: XCTestCase {
    func testMatchesXeneonByIdentityAndResolution() {
        let display = makeDisplay(
            name: "Unknown Display",
            vendor: TargetDisplaySelector.xeneonVendor,
            model: TargetDisplaySelector.xeneonModel,
            width: 2_560,
            height: 720
        )

        XCTAssertTrue(TargetDisplaySelector.isXeneonCandidate(display))
    }

    func testRejectsWrongResolution() {
        let display = makeDisplay(
            name: "XENEON EDGE",
            vendor: TargetDisplaySelector.xeneonVendor,
            model: TargetDisplaySelector.xeneonModel,
            width: 1_920,
            height: 1_080
        )

        XCTAssertFalse(TargetDisplaySelector.isXeneonCandidate(display))
    }

    func testPreferredDisplayWinsOverAutomaticDetection() {
        let preferred = makeDisplay(
            uuid: "preferred",
            name: "Studio Display",
            vendor: 1,
            model: 2,
            width: 1_920,
            height: 1_080
        )
        let xeneon = makeDisplay(
            uuid: "xeneon",
            name: "XENEON EDGE",
            vendor: TargetDisplaySelector.xeneonVendor,
            model: TargetDisplaySelector.xeneonModel,
            width: 2_560,
            height: 720
        )

        let result = TargetDisplaySelector().resolve(from: [xeneon, preferred], preferredUUID: "preferred")

        XCTAssertEqual(result?.uuid, "preferred")
    }

    private func makeDisplay(
        uuid: String = "test-display",
        name: String,
        vendor: UInt32,
        model: UInt32,
        width: Int,
        height: Int
    ) -> DashboardDisplay {
        DashboardDisplay(
            id: 1,
            uuid: uuid,
            name: name,
            vendorNumber: vendor,
            modelNumber: model,
            serialNumber: 1,
            pixelWidth: width,
            pixelHeight: height,
            screen: NSScreen.main ?? NSScreen.screens[0]
        )
    }
}
