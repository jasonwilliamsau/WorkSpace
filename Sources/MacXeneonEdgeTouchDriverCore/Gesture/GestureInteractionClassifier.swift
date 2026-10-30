import ApplicationServices
import CoreGraphics
import Foundation

/// The native interaction expected at the initial touchscreen contact point.
public enum GestureInteractionKind: Equatable {
    case content
    case windowChrome
    case menu
}

/// Classifies the native UI under a mapped touchscreen contact.
public protocol GestureInteractionClassifying: AnyObject {
    func classify(at point: CGPoint, displayBounds: CGRect) -> GestureInteractionKind
}

/// Conservative fallback used by tests and hosts without Accessibility access.
public final class ContentGestureInteractionClassifier: GestureInteractionClassifying {
    public init() {}

    public func classify(at point: CGPoint, displayBounds: CGRect) -> GestureInteractionKind {
        .content
    }
}

/// Uses Accessibility hit-testing to distinguish content, draggable title bars, and menus.
public final class AXGestureInteractionClassifier: GestureInteractionClassifying {
    private let systemWideElement: AXUIElement
    private let titleBarMaximumHeight: CGFloat
    private let menuBarFallbackHeight: CGFloat

    public init(
        systemWideElement: AXUIElement = AXUIElementCreateSystemWide(),
        titleBarMaximumHeight: CGFloat = 48,
        menuBarFallbackHeight: CGFloat = 32
    ) {
        self.systemWideElement = systemWideElement
        self.titleBarMaximumHeight = titleBarMaximumHeight
        self.menuBarFallbackHeight = menuBarFallbackHeight
    }

    public func classify(at point: CGPoint, displayBounds: CGRect) -> GestureInteractionKind {
        var hitElement: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard hitResult == .success, let hitElement else {
            return isInDisplayMenuBar(point, displayBounds: displayBounds) ? .menu : .content
        }

        let role = stringAttribute(hitElement, kAXRoleAttribute)
        let subrole = stringAttribute(hitElement, kAXSubroleAttribute)

        if isMenuRole(role) || isMenuRole(subrole) {
            return .menu
        }

        if isInDisplayMenuBar(point, displayBounds: displayBounds), role != kAXWindowRole {
            return .menu
        }

        guard !isInteractiveWindowControl(role),
              let window = containingWindow(for: hitElement, role: role),
              let frame = frame(of: window),
              point.y >= frame.minY,
              point.y <= frame.minY + min(titleBarMaximumHeight, frame.height) else {
            return .content
        }

        return .windowChrome
    }

    private func isInDisplayMenuBar(_ point: CGPoint, displayBounds: CGRect) -> Bool {
        point.y >= displayBounds.minY &&
            point.y <= displayBounds.minY + min(menuBarFallbackHeight, displayBounds.height)
    }

    private func isMenuRole(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == kAXMenuBarRole ||
            value == kAXMenuBarItemRole ||
            value == kAXMenuRole ||
            value == kAXMenuItemRole
    }

    private func isInteractiveWindowControl(_ role: String?) -> Bool {
        guard let role else { return false }
        return role == kAXButtonRole ||
            role == kAXCheckBoxRole ||
            role == kAXPopUpButtonRole ||
            role == kAXMenuButtonRole ||
            role == kAXTextFieldRole ||
            role == kAXTextAreaRole ||
            role == kAXToolbarRole
    }

    private func containingWindow(for element: AXUIElement, role: String?) -> AXUIElement? {
        if role == kAXWindowRole {
            return element
        }
        return elementAttribute(element, kAXWindowAttribute)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = valueAttribute(element, kAXPositionAttribute),
              let sizeValue = valueAttribute(element, kAXSizeAttribute) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func valueAttribute(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }
}
