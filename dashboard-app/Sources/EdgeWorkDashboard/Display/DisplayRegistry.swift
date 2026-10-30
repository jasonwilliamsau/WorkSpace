import AppKit
import CoreGraphics
import Foundation

struct DashboardDisplay: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let pixelWidth: Int
    let pixelHeight: Int
    let screen: NSScreen

    static func == (lhs: DashboardDisplay, rhs: DashboardDisplay) -> Bool {
        lhs.id == rhs.id && lhs.uuid == rhs.uuid && lhs.screen.frame == rhs.screen.frame
    }
}

final class DisplayRegistry {
    func activeDisplays() -> [DashboardDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayIsActive(id) != 0 else { return nil }

            return DashboardDisplay(
                id: id,
                uuid: displayUUID(id),
                name: screen.localizedName,
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                pixelWidth: CGDisplayPixelsWide(id),
                pixelHeight: CGDisplayPixelsHigh(id),
                screen: screen
            )
        }
    }

    private func displayUUID(_ id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(kCFAllocatorDefault, uuid) else {
            return "display-\(id)"
        }
        return string as String
    }
}

final class TargetDisplaySelector {
    static let xeneonVendor: UInt32 = 3_672
    static let xeneonModel: UInt32 = 60_672
    static let expectedWidth = 2_560
    static let expectedHeight = 720

    func resolve(from displays: [DashboardDisplay], preferredUUID: String?) -> DashboardDisplay? {
        if let preferredUUID,
           let saved = displays.first(where: { $0.uuid == preferredUUID }) {
            return saved
        }

        let candidates = displays.filter(Self.isXeneonCandidate)
        guard candidates.count == 1 else { return nil }
        return candidates.first
    }

    static func isXeneonCandidate(_ display: DashboardDisplay) -> Bool {
        let nameMatches = display.name.localizedCaseInsensitiveContains("XENEON EDGE")
        let identityMatches = display.vendorNumber == xeneonVendor && display.modelNumber == xeneonModel
        let resolutionMatches = display.pixelWidth == expectedWidth && display.pixelHeight == expectedHeight
        return resolutionMatches && (nameMatches || identityMatches)
    }
}
