import AppKit
import SwiftUI

enum DashboardColor {
    static func color(from hex: String) -> Color {
        guard let normalized = normalizedHex(hex) else { return Color.accentColor }
        let digits = String(normalized.dropFirst())
        guard let value = UInt64(digits, radix: 16) else { return Color.accentColor }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(from color: Color) -> String {
        guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else { return "#8D7CFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded())
        )
    }

    static func normalizedHex(_ value: String) -> String? {
        let candidate = value.hasPrefix("#") ? value : "#\(value)"
        guard candidate.count == 7,
              candidate.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
        return candidate.uppercased()
    }
}
