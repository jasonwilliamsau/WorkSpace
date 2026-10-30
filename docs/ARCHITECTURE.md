# Architecture

## Components

```text
XENEON EDGE touch hardware
        |
        v
touch-driver
  - observes the HID touchscreen
  - maps coordinates to the selected display
  - synthesizes context-aware pointer gestures
        |
        v
dashboard-app
  - AppKit display and window lifecycle
  - SwiftUI Preferences and configuration
  - allowlisted native application and terminal actions
  - WKWebView touch-first dashboard
```

The driver and dashboard are deliberately separate processes. The driver owns privileged input routing; the dashboard consumes its health state but does not receive arbitrary HID access.

## Configuration

The dashboard stores versioned JSON under the current user's Application Support directory. Migrations preserve older schema versions. Portable exports remove machine-specific display identifiers, application paths, and security-scoped bookmarks.

## Native bridge

The web dashboard sends typed, allowlisted actions to Swift. It cannot execute arbitrary shell commands. Folder actions resolve configured application bundle identifiers and validated folder URLs before asking macOS to open them.

## Terminal integration

Terminal support is provider-based. The current adapters support iTerm2 and macOS Terminal through Apple events. A folder terminal action always receives one explicit configured folder URL.

## Distribution boundary

Source builds use ad-hoc signing. Public releases still require a stable bundle identifier, Developer ID signing, hardened runtime validation, notarisation, and a versioned update strategy.
