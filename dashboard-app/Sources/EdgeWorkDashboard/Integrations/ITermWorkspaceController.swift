import AppKit
import Foundation

enum TerminalWorkspaceError: LocalizedError {
    case noWorkspaces
    case providerNotInstalled(String)
    case unsupportedLayout(provider: String, layout: String)
    case scriptFailed(provider: String, message: String)

    var errorDescription: String? {
        switch self {
        case .noWorkspaces:
            "Choose a folder before opening the terminal."
        case .providerNotInstalled(let provider):
            "\(provider) is not installed. Choose another terminal in Preferences."
        case .unsupportedLayout(let provider, let layout):
            "\(provider) does not support the \(layout) arrangement."
        case .scriptFailed(let provider, let message):
            "Could not create the \(provider) workspace: \(message)"
        }
    }
}

struct TerminalCapabilities: Equatable {
    let layouts: [TerminalLayout]

    func supports(_ layout: TerminalLayout) -> Bool {
        layouts.contains(layout)
    }
}

protocol TerminalProvider {
    var id: TerminalProviderID { get }
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var capabilities: TerminalCapabilities { get }

    func showWorkspace(
        directories: [URL],
        layout: TerminalLayout,
        reuseExistingSession: Bool,
        screenBounds: CGRect
    ) throws
    func hide()
}

final class ITermWorkspaceController {
    private let providers: [TerminalProviderID: any TerminalProvider]
    private var activeProviderID: TerminalProviderID?

    init(providers: [any TerminalProvider] = [ITerm2Provider(), MacOSTerminalProvider()]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    func capabilities(for providerID: TerminalProviderID) -> TerminalCapabilities {
        providers[providerID]?.capabilities ?? TerminalCapabilities(layouts: [])
    }

    func showWorkspace(
        directories: [URL],
        preferences: TerminalPreferences,
        screenBounds: CGRect
    ) throws {
        guard !directories.isEmpty else { throw TerminalWorkspaceError.noWorkspaces }
        guard let provider = providers[preferences.provider] else {
            throw TerminalWorkspaceError.providerNotInstalled(preferences.provider.displayName)
        }
        guard provider.capabilities.supports(preferences.layout) else {
            throw TerminalWorkspaceError.unsupportedLayout(
                provider: provider.displayName,
                layout: preferences.layout.displayName
            )
        }

        try provider.showWorkspace(
            directories: directories,
            layout: preferences.layout,
            reuseExistingSession: preferences.reuseExistingSession,
            screenBounds: screenBounds
        )
        activeProviderID = preferences.provider
    }

    func hideTerminal() {
        guard let activeProviderID else { return }
        providers[activeProviderID]?.hide()
    }
}

final class ITerm2Provider: TerminalProvider {
    let id = TerminalProviderID.iTerm2
    let displayName = "iTerm2"
    let bundleIdentifier = "com.googlecode.iterm2"
    let capabilities = TerminalCapabilities(layouts: TerminalLayout.allCases)

    private var workspaceCreated = false

    func showWorkspace(
        directories: [URL],
        layout: TerminalLayout,
        reuseExistingSession: Bool,
        screenBounds: CGRect
    ) throws {
        try ensureInstalledAndRunning(bundleIdentifier: bundleIdentifier, displayName: displayName)

        if reuseExistingSession, workspaceCreated,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }

        let commands = directories.map { appleScriptString(cdCommand(for: $0)) }
        let script: String
        switch layout {
        case .tabs:
            script = tabScript(commands: commands, screenBounds: screenBounds)
        case .splitVertically:
            script = splitScript(commands: commands, direction: "vertically", screenBounds: screenBounds)
        case .splitHorizontally:
            script = splitScript(commands: commands, direction: "horizontally", screenBounds: screenBounds)
        case .windows:
            script = windowScript(commands: commands, screenBounds: screenBounds)
        }
        try executeAppleScript(script, provider: displayName)
        workspaceCreated = true
    }

    func hide() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.hide()
    }

    private func tabScript(commands: [String], screenBounds: CGRect) -> String {
        let remaining = commands.dropFirst().map { command in
            """
            tell dashboardWindow
                set newTab to (create tab with default profile)
                tell current session of newTab to write text \"\(command)\"
            end tell
            """
        }.joined(separator: "\n")
        return """
        tell application "iTerm"
            activate
            set dashboardWindow to (create window with default profile)
            set bounds of dashboardWindow to \(appleScriptBounds(screenBounds))
            tell current session of dashboardWindow to write text "\(commands[0])"
            \(remaining)
        end tell
        """
    }

    private func splitScript(commands: [String], direction: String, screenBounds: CGRect) -> String {
        let remaining = commands.dropFirst().map { command in
            """
            tell dashboardWindow
                tell current session
                    set newSession to (split \(direction) with default profile)
                end tell
                tell newSession to write text \"\(command)\"
            end tell
            """
        }.joined(separator: "\n")
        return """
        tell application "iTerm"
            activate
            set dashboardWindow to (create window with default profile)
            set bounds of dashboardWindow to \(appleScriptBounds(screenBounds))
            tell current session of dashboardWindow to write text "\(commands[0])"
            \(remaining)
        end tell
        """
    }

    private func windowScript(commands: [String], screenBounds: CGRect) -> String {
        commands.map { command in
            """
            tell application "iTerm"
                activate
                set dashboardWindow to (create window with default profile)
                set bounds of dashboardWindow to \(appleScriptBounds(screenBounds))
                tell current session of dashboardWindow to write text "\(command)"
            end tell
            """
        }.joined(separator: "\n")
    }
}

final class MacOSTerminalProvider: TerminalProvider {
    let id = TerminalProviderID.macOSTerminal
    let displayName = "macOS Terminal"
    let bundleIdentifier = "com.apple.Terminal"
    let capabilities = TerminalCapabilities(layouts: [.windows])

    private var workspaceCreated = false

    func showWorkspace(
        directories: [URL],
        layout: TerminalLayout,
        reuseExistingSession: Bool,
        screenBounds: CGRect
    ) throws {
        guard capabilities.supports(layout) else {
            throw TerminalWorkspaceError.unsupportedLayout(provider: displayName, layout: layout.displayName)
        }
        try ensureInstalledAndRunning(bundleIdentifier: bundleIdentifier, displayName: displayName)

        if reuseExistingSession, workspaceCreated,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }

        let commands = directories.map { appleScriptString(cdCommand(for: $0)) }
        let bounds = appleScriptBounds(screenBounds)
        let windows = commands.map { command in
            """
            do script "\(command)"
            set bounds of front window to \(bounds)
            """
        }.joined(separator: "\n")
        let script = """
        tell application "Terminal"
            activate
            \(windows)
        end tell
        """
        try executeAppleScript(script, provider: displayName)
        workspaceCreated = true
    }

    func hide() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.hide()
    }
}

private func ensureInstalledAndRunning(bundleIdentifier: String, displayName: String) throws {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        throw TerminalWorkspaceError.providerNotInstalled(displayName)
    }
    if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        if let launchError { throw launchError }
    }
}

private func executeAppleScript(_ source: String, provider: String) throws {
    var errorInfo: NSDictionary?
    guard NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) != nil else {
        let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        throw TerminalWorkspaceError.scriptFailed(provider: provider, message: message)
    }
}

private func cdCommand(for url: URL) -> String {
    "cd -- \(shellQuote(url.path))"
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func appleScriptBounds(_ frame: CGRect) -> String {
    let left = Int(frame.minX.rounded())
    let top = Int(frame.minY.rounded())
    let right = Int(frame.maxX.rounded())
    let bottom = Int(frame.maxY.rounded())
    return "{\(left), \(top), \(right), \(bottom)}"
}
