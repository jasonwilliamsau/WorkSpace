import AppKit
import Foundation

@MainActor
final class EdgeDashboardApplication: NSObject {
    private let displayRegistry = DisplayRegistry()
    private let displaySelector = TargetDisplaySelector()
    private let driverHealthProvider = DriverHealthProvider()
    private let systemMetricsProvider = SystemMetricsProvider()
    private let terminalController = ITermWorkspaceController()
    private let preferencesStore = PreferencesStore()
    private var windowController: DashboardWindowController?
    private var observers: [NSObjectProtocol] = []
    private var statusItem: NSStatusItem?
    private lazy var preferencesWindowController = PreferencesWindowController(
        store: preferencesStore,
        displays: { [weak self] in self?.displayRegistry.activeDisplays() ?? [] }
    )

    func start() {
        configureStatusItem()
        preferencesStore.onChange = { [weak self] preferences in
            self?.applyPreferences(preferences)
        }
        resolveAndPresentDashboard()
        if !preferencesStore.preferences.general.hasCompletedSetup {
            preferencesWindowController.show()
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resolveAndPresentDashboard() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resolveAndPresentDashboard() }
        })
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        driverHealthProvider.stop()
        systemMetricsProvider.stop()
        preferencesWindowController.close()
        windowController?.close()
        windowController = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func resolveAndPresentDashboard() {
        let displays = displayRegistry.activeDisplays()
        guard let target = displaySelector.resolve(
            from: displays,
            preferredUUID: preferencesStore.preferences.display.targetDisplayUUID
        ) else {
            presentFallback(message: "Choose a dashboard display in Preferences")
            return
        }

        if preferencesStore.preferences.display.targetDisplayUUID == nil {
            preferencesStore.preferences.display.targetDisplayUUID = target.uuid
            preferencesStore.preferences.display.targetDisplayName = target.name
        }

        if let windowController {
            windowController.move(to: target)
            return
        }

        let controller = DashboardWindowController(
            display: target,
            terminalController: terminalController,
            preferencesStore: preferencesStore
        )
        controller.onShowPreferences = { [weak self] in self?.preferencesWindowController.show() }
        controller.onRequestRefresh = { [weak self] in
            self?.driverHealthProvider.refreshNow()
        }
        windowController = controller
        controller.showDashboard()

        driverHealthProvider.onUpdate = { [weak controller] health in
            controller?.updateDriverHealth(health)
        }
        driverHealthProvider.start()
        systemMetricsProvider.onUpdate = { [weak controller] metrics in
            controller?.updateSystemMetrics(metrics)
        }
        systemMetricsProvider.start()
    }

    private func presentFallback(message: String) {
        if let windowController {
            windowController.updateDisplayMessage(message)
            return
        }

        guard let fallback = displayRegistry.activeDisplays().first else { return }
        let controller = DashboardWindowController(
            display: fallback,
            terminalController: terminalController,
            preferencesStore: preferencesStore
        )
        controller.onShowPreferences = { [weak self] in self?.preferencesWindowController.show() }
        windowController = controller
        controller.updateDisplayMessage(message)
        controller.showDashboard()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.inset.filled.and.person.filled",
            accessibilityDescription: "EDGE Work Dashboard"
        )

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "Show Dashboard",
            action: #selector(showDashboardFromMenu),
            keyEquivalent: "d"
        )
        showItem.target = self
        menu.addItem(showItem)

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferencesFromMenu),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit EDGE Work Dashboard",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func showDashboardFromMenu() {
        resolveAndPresentDashboard()
        windowController?.showDashboard()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func showPreferencesFromMenu() {
        preferencesWindowController.show()
    }

    private func applyPreferences(_ preferences: AppPreferences) {
        windowController?.updatePreferences(preferences)
        resolveAndPresentDashboard()
    }
}
