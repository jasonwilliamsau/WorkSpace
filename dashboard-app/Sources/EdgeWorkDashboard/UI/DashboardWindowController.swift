import AppKit
import Foundation
import WebKit

final class DashboardPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DashboardWindowController: NSObject {
    var onRequestRefresh: (() -> Void)?
    var onShowPreferences: (() -> Void)?

    private let window: NSWindow
    private let webController: DashboardWebViewController
    private let terminalController: ITermWorkspaceController
    private let preferencesStore: PreferencesStore
    private let returnPanel: NSPanel
    private var display: DashboardDisplay
    private var activeWorkspaceID: UUID
    private var escapeKeyMonitor: Any?

    init(
        display: DashboardDisplay,
        terminalController: ITermWorkspaceController,
        preferencesStore: PreferencesStore
    ) {
        self.display = display
        self.terminalController = terminalController
        self.preferencesStore = preferencesStore
        self.activeWorkspaceID = UUID(uuidString: preferencesStore.preferences.general.startWorkspace)
            ?? preferencesStore.preferences.workspaces.first?.id
            ?? AppPreferences.defaultWorkspaceID
        self.webController = DashboardWebViewController()
        self.window = DashboardPanelWindow(
            contentRect: display.screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: display.screen
        )
        self.returnPanel = DashboardWindowController.makeReturnPanel(screen: display.screen)
        super.init()

        window.backgroundColor = NSColor.black
        window.contentViewController = webController
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.setFrame(display.screen.frame, display: false)

        webController.onAction = { [weak self] action in
            self?.handle(action)
        }
        webController.onReady = { [weak self] in
            guard let self else { return }
            self.updatePreferences(self.preferencesStore.preferences)
        }
        configureReturnButton()
        configureEscapeKeyMonitor()
    }

    func showDashboard() {
        terminalController.hideTerminal()
        returnPanel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(display.screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    func move(to newDisplay: DashboardDisplay) {
        guard newDisplay != display else { return }
        display = newDisplay
        window.setFrame(newDisplay.screen.frame, display: true)
        positionReturnPanel(on: newDisplay.screen)
    }

    func updateDriverHealth(_ health: DriverHealth) {
        webController.updateDriverHealth(health)
    }

    func updateDisplayMessage(_ message: String) {
        webController.updateDisplayMessage(message)
    }

    func updateSystemMetrics(_ metrics: SystemMetrics) {
        webController.updateSystemMetrics(metrics)
    }

    func updatePreferences(_ preferences: AppPreferences) {
        if !preferences.workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = UUID(uuidString: preferences.general.startWorkspace)
                ?? preferences.workspaces.first?.id
                ?? AppPreferences.defaultWorkspaceID
        }
        webController.updatePreferences(DashboardPreferencesSnapshot(
            preferences: preferences,
            applicationIcon: { [weak self] in self?.applicationIconDataURL(for: $0) },
            applicationAvailable: { [weak self] in self?.preferencesStore.resolvedURL(for: $0) != nil }
        ))
    }

    func close() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
        returnPanel.close()
        window.close()
    }

    private func configureEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.window.isKeyWindow else { return event }
            self.webController.dismissOverlays()
            return nil
        }
    }

    private func handle(_ action: DashboardAction) {
        switch action {
        case .showDashboard:
            showDashboard()
        case .selectWorkspace(let workspaceID):
            if preferencesStore.preferences.workspaces.contains(where: { $0.id == workspaceID }) {
                activeWorkspaceID = workspaceID
            }
        case .openFolder(let folderID, let application):
            openFolder(folderID, with: application)
        case .openFolderInTerminal(let folderID):
            openFolderInTerminal(folderID)
        case .openFolderRecipe(let folderID, let applicationID):
            openFolder(folderID, with: applicationID)
            openFolderInTerminal(folderID)
        case .addFolders:
            chooseFolders()
        case .focusOverlay:
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(webController.view)
        case .refresh:
            onRequestRefresh?()
        case .showPreferences:
            onShowPreferences?()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func openFolder(_ folderID: UUID, with applicationID: UUID) {
        guard let folder = preferencesStore.preferences.folders.first(where: { $0.id == folderID }) else {
            webController.presentActionError("Folder is no longer configured")
            return
        }
        guard let configuredApplication = preferencesStore.preferences.applications.first(where: {
            $0.id == applicationID && $0.isEnabled
        }) else {
            webController.presentActionError("Application is no longer available")
            return
        }
        guard let application = preferencesStore.resolvedURL(for: configuredApplication) else {
            webController.presentActionError("\(configuredApplication.name) is not installed")
            return
        }
        let folderURL = preferencesStore.resolvedURL(for: folder)
        let accessed = folderURL.startAccessingSecurityScopedResource()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: application,
            configuration: configuration
        ) { [weak self] _, error in
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
            if let error {
                Task { @MainActor in
                    self?.webController.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    private func openFolderInTerminal(_ folderID: UUID) {
        guard let folder = preferencesStore.preferences.folders.first(where: { $0.id == folderID }) else {
            webController.presentActionError("Folder is no longer configured")
            return
        }
        var terminalPreferences = preferencesStore.preferences.terminal
        terminalPreferences.layout = .windows
        terminalPreferences.reuseExistingSession = false
        do {
            try terminalController.showWorkspace(
                directories: [preferencesStore.resolvedURL(for: folder)],
                preferences: terminalPreferences,
                screenBounds: CGDisplayBounds(display.id)
            )
            window.orderOut(nil)
            positionReturnPanel(on: display.screen)
            returnPanel.orderFrontRegardless()
        } catch {
            webController.presentActionError(error.localizedDescription)
        }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Add Folders to Workspace"
        panel.prompt = "Add Selected"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        preferencesStore.addFolders(urls: panel.urls, to: activeWorkspaceID)
    }

    private func applicationIconDataURL(for application: ApplicationPreferences) -> String? {
        guard let applicationURL = preferencesStore.resolvedURL(for: application) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 48, height: 48)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private func configureReturnButton() {
        guard let button = returnPanel.contentView?.subviews.compactMap({ $0 as? NSButton }).first else { return }
        button.target = self
        button.action = #selector(returnToDashboard)
    }

    @objc private func returnToDashboard() {
        showDashboard()
    }

    private func positionReturnPanel(on screen: NSScreen) {
        let size = returnPanel.frame.size
        let origin = CGPoint(
            x: screen.frame.maxX - size.width - 24,
            y: screen.frame.maxY - size.height - 24
        )
        returnPanel.setFrameOrigin(origin)
    }

    private static func makeReturnPanel(screen: NSScreen) -> NSPanel {
        let frame = CGRect(x: 0, y: 0, width: 220, height: 64)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.96)
        panel.hasShadow = true

        let button = NSButton(title: "Return to Dashboard", target: nil, action: nil)
        button.frame = frame.insetBy(dx: 8, dy: 8)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        panel.contentView?.addSubview(button)
        return panel
    }
}
