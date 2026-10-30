import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PreferencesWindowController: NSWindowController {
    private var colorPanelObserver: NSObjectProtocol?

    init(store: PreferencesStore, displays: @escaping () -> [DashboardDisplay]) {
        let root = PreferencesView(store: store, displays: displays)
        let hostingController = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EDGE Work Dashboard Preferences"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        observeColorPanel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let colorPanelObserver { NotificationCenter.default.removeObserver(colorPanelObserver) }
    }

    private func observeColorPanel() {
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? NSColorPanel else { return }
            Task { @MainActor in self?.positionColorPanel(panel) }
        }
    }

    private func positionColorPanel(_ panel: NSColorPanel) {
        guard let preferencesWindow = window, let screen = preferencesWindow.screen else { return }
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let spacing: CGFloat = 12
        var x = preferencesWindow.frame.maxX + spacing
        if x + panelSize.width > visibleFrame.maxX {
            x = preferencesWindow.frame.minX - panelSize.width - spacing
        }
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        let preferredY = preferencesWindow.frame.maxY - panelSize.height
        let y = min(max(preferredY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
}

@MainActor
private struct PreferencesView: View {
    @ObservedObject var store: PreferencesStore
    let displays: () -> [DashboardDisplay]

    @State private var selectedSection = PreferencesSection.workspaces
    @State private var activeDisplays: [DashboardDisplay] = []
    @State private var applicationError: String?
    @State private var configurationMessage: String?
    @StateObject private var loginItemController = LoginItemController()

    var body: some View {
        NavigationSplitView {
            List(PreferencesSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 14) {
                if !store.preferences.general.hasCompletedSetup { setupBanner }
                Group {
                    switch selectedSection {
                    case .general: generalSettings
                    case .workspaces: workspaceSettings
                    case .applications: applicationSettings
                    case .terminal: terminalSettings
                    case .display: displaySettings
                    case .configuration: configurationSettings
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 620)
        .onAppear {
            activeDisplays = displays()
            loginItemController.refresh()
        }
        .alert("Could Not Add Application", isPresented: Binding(
            get: { applicationError != nil },
            set: { if !$0 { applicationError = nil } }
        )) {
            Button("OK", role: .cancel) { applicationError = nil }
        } message: {
            Text(applicationError ?? "Unknown error")
        }
        .alert("Configuration", isPresented: Binding(
            get: { configurationMessage != nil },
            set: { if !$0 { configurationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { configurationMessage = nil }
        } message: {
            Text(configurationMessage ?? "")
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish setting up your dashboard").font(.headline)
                Text("Add at least one folder and enable an application, then complete setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Workspaces") { selectedSection = .workspaces }
            Button("Applications") { selectedSection = .applications }
            Button("Complete Setup") { store.preferences.general.hasCompletedSetup = true }
                .buttonStyle(.borderedProminent)
                .disabled(!setupReady)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var setupReady: Bool {
        !store.preferences.folders.isEmpty && store.preferences.applications.contains(where: \.isEnabled)
    }

    private var generalSettings: some View {
        settingsForm(title: "General", subtitle: "Choose how the dashboard identifies itself and starts.") {
            TextField("Dashboard title", text: binding(
                get: { store.preferences.general.dashboardTitle },
                set: { store.preferences.general.dashboardTitle = $0 }
            ))
            Picker("Start workspace", selection: binding(
                get: { store.preferences.general.startWorkspace },
                set: { store.preferences.general.startWorkspace = $0 }
            )) {
                ForEach(store.preferences.workspaces) { workspace in
                    Text(workspace.name).tag(workspace.id.uuidString)
                }
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItemController.isEnabled },
                set: { enabled in
                    do {
                        try loginItemController.setEnabled(enabled)
                    } catch {
                        configurationMessage = error.localizedDescription
                        loginItemController.refresh()
                    }
                }
            ))
            Text(loginItemController.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if loginItemController.requiresApproval {
                Button("Open Login Items Settings") { loginItemController.openSystemSettings() }
            }
        }
    }

    private var workspaceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHeader(
                title: "Workspaces",
                subtitle: "Create dashboard workspaces, then add the folders that belong to each one."
            )
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(store.preferences.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        workspaceCard(workspace, index: index)
                    }
                }
                .padding(.trailing, 8)
            }
            Button("Add Workspace", systemImage: "plus") { store.addWorkspace() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func workspaceCard(_ workspace: DashboardWorkspacePreferences, index: Int) -> some View {
        let folderIndices = store.preferences.folders.indices.filter {
            store.preferences.folders[$0].workspaceID == workspace.id
        }
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ColorPicker(
                        "Workspace colour",
                        selection: colorBinding(
                            get: { store.preferences.workspaces[index].color },
                            set: { store.preferences.workspaces[index].color = $0 }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 30)
                    TextField("Workspace name", text: binding(
                        get: { store.preferences.workspaces[index].name },
                        set: { store.preferences.workspaces[index].name = $0 }
                    ))
                    .font(.headline)
                    TextField("Label", text: binding(
                        get: { store.preferences.workspaces[index].shortLabel },
                        set: { store.preferences.workspaces[index].shortLabel = String($0.uppercased().prefix(4)) }
                    ))
                    .frame(width: 70)
                    Button { store.moveWorkspace(id: workspace.id, direction: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button { store.moveWorkspace(id: workspace.id, direction: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == store.preferences.workspaces.count - 1)
                    Button(role: .destructive) { store.removeWorkspace(id: workspace.id) } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.preferences.workspaces.count == 1)
                }

                Divider()
                if folderIndices.isEmpty {
                    Text("No folders in this workspace.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(folderIndices.enumerated()), id: \.element) { position, folderIndex in
                        folderRow(
                            store.preferences.folders[folderIndex],
                            index: folderIndex,
                            position: position,
                            count: folderIndices.count
                        )
                        if position < folderIndices.count - 1 { Divider() }
                    }
                }
                Button("Add Folders…", systemImage: "folder.badge.plus") {
                    chooseFolders(for: workspace.id)
                }
            }
            .padding(6)
        }
    }

    private func folderRow(_ folder: FolderPreferences, index: Int, position: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ColorPicker(
                    "Folder colour",
                    selection: colorBinding(
                        get: { store.preferences.folders[index].color },
                        set: { store.preferences.folders[index].color = $0 }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 30)
                TextField("Folder name", text: binding(
                    get: { store.preferences.folders[index].name },
                    set: { store.preferences.folders[index].name = $0 }
                ))
                TextField("Icon", text: binding(
                    get: { store.preferences.folders[index].icon },
                    set: { store.preferences.folders[index].icon = String($0.uppercased().prefix(3)) }
                ))
                .frame(width: 65)
                Button { store.moveFolder(id: folder.id, direction: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(position == 0)
                Button { store.moveFolder(id: folder.id, direction: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(position == count - 1)
                Button(role: .destructive) { store.removeFolder(id: folder.id) } label: { Image(systemName: "trash") }
            }
            HStack {
                Text(folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Picker("Workspace", selection: binding(
                    get: { store.preferences.folders[index].workspaceID ?? store.preferences.workspaces[0].id },
                    set: { store.preferences.folders[index].workspaceID = $0 }
                )) {
                    ForEach(store.preferences.workspaces) { item in Text(item.name).tag(item.id) }
                }
                .frame(width: 180)
                Button("Change Folder…") { chooseFolderLocation(for: folder.id) }
            }
            folderApplicationSettings(folder, index: index)
        }
        .padding(.vertical, 4)
    }

    private func folderApplicationSettings(_ folder: FolderPreferences, index: Int) -> some View {
        let selectedIDs = store.effectiveApplicationIDs(for: folder)
        let enabledApplications = store.preferences.applications.filter {
            $0.isEnabled && store.resolvedURL(for: $0) != nil
        }
        let orderedApplications = selectedIDs.compactMap { id in
            enabledApplications.first { $0.id == id }
        } + enabledApplications.filter { !selectedIDs.contains($0.id) }

        return DisclosureGroup("Folder Actions") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Main tap", selection: binding(
                    get: { store.preferences.folders[index].primaryAction },
                    set: { store.preferences.folders[index].primaryAction = $0 }
                )) {
                    ForEach(FolderPrimaryAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                Picker("Default application", selection: Binding<UUID?>(
                    get: { store.preferences.folders[index].defaultApplicationID },
                    set: { store.setFolderDefaultApplication(folderID: folder.id, applicationID: $0) }
                )) {
                    Text("Inherit global default").tag(nil as UUID?)
                    ForEach(enabledApplications.filter { selectedIDs.contains($0.id) }) { application in
                        Text(application.name).tag(application.id as UUID?)
                    }
                }

                ForEach(Array(orderedApplications.enumerated()), id: \.element.id) { position, application in
                    let selected = selectedIDs.contains(application.id)
                    HStack {
                        Toggle(application.name, isOn: Binding(
                            get: {
                                store.effectiveApplicationIDs(for: store.preferences.folders[index])
                                    .contains(application.id)
                            },
                            set: {
                                store.setFolderApplication(
                                    folderID: folder.id,
                                    applicationID: application.id,
                                    enabled: $0
                                )
                            }
                        ))
                        Spacer()
                        Button {
                            store.moveFolderApplication(folderID: folder.id, applicationID: application.id, direction: -1)
                        } label: { Image(systemName: "arrow.up") }
                        .disabled(!selected || position == 0)
                        Button {
                            store.moveFolderApplication(folderID: folder.id, applicationID: application.id, direction: 1)
                        } label: { Image(systemName: "arrow.down") }
                        .disabled(!selected || position >= selectedIDs.count - 1)
                    }
                }

                Button("Use Global Application Settings") {
                    store.resetFolderApplications(folderID: folder.id)
                }
                .disabled(folder.applicationIDs == nil && folder.defaultApplicationID == nil)
            }
            .padding(.top, 8)
        }
    }

    private var applicationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHeader(
                title: "Applications",
                subtitle: "Choose which macOS applications appear in each folder’s action menu."
            )
            List {
                ForEach(Array(store.preferences.applications.enumerated()), id: \.element.id) { index, application in
                    let isAvailable = store.resolvedURL(for: application) != nil
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { store.preferences.applications[index].isEnabled },
                            set: { store.setApplicationEnabled(id: application.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        TextField("Application name", text: binding(
                            get: { store.preferences.applications[index].name },
                            set: { store.preferences.applications[index].name = $0 }
                        ))
                        VStack(alignment: .leading) {
                            Text(application.bundleIdentifier).font(.caption.monospaced())
                            if store.preferences.editor.defaultApplicationID == application.id {
                                Text("DEFAULT").font(.caption2.bold()).foregroundStyle(.tint)
                            } else if !isAvailable {
                                Text("NOT INSTALLED").font(.caption2.bold()).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Make Default") { store.setDefaultApplication(id: application.id) }
                            .disabled(
                                !application.isEnabled || !isAvailable ||
                                    store.preferences.editor.defaultApplicationID == application.id
                            )
                        Button { store.moveApplication(id: application.id, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button { store.moveApplication(id: application.id, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == store.preferences.applications.count - 1)
                        Button(role: .destructive) { store.removeApplication(id: application.id) } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(application.isBuiltIn)
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
            Button("Add Application…", systemImage: "plus") { chooseApplication() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var terminalSettings: some View {
        settingsForm(title: "Terminal", subtitle: "Choose the terminal used by each folder’s Open in Terminal action.") {
            Picker("Terminal", selection: binding(
                get: { store.preferences.terminal.provider },
                set: { provider in
                    store.preferences.terminal.provider = provider
                    if provider == .macOSTerminal, store.preferences.terminal.layout != .windows {
                        store.preferences.terminal.layout = .windows
                    }
                }
            )) {
                ForEach(TerminalProviderID.allCases) { provider in Text(provider.displayName).tag(provider) }
            }
        }
    }

    private var displaySettings: some View {
        settingsForm(title: "Display", subtitle: "Choose the screen that owns the borderless dashboard window.") {
            Picker("Dashboard display", selection: binding(
                get: { store.preferences.display.targetDisplayUUID ?? "" },
                set: { uuid in
                    let selected = activeDisplays.first { $0.uuid == uuid }
                    store.preferences.display.targetDisplayUUID = selected?.uuid
                    store.preferences.display.targetDisplayName = selected?.name
                }
            )) {
                Text("Automatic XENEON detection").tag("")
                ForEach(activeDisplays, id: \.uuid) { display in
                    Text("\(display.name) — \(display.pixelWidth)×\(display.pixelHeight)").tag(display.uuid)
                }
            }
            Button("Refresh Displays") { activeDisplays = displays() }
        }
    }

    private var configurationSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsHeader(
                title: "Configuration",
                subtitle: "Back up your dashboard or move its setup to another Mac."
            )
            GroupBox("Portable JSON") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Exports include workspaces, folders, colours, applications, and terminal settings. Display identifiers and security bookmarks are excluded because they are specific to this Mac.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Export Configuration…", systemImage: "square.and.arrow.up") {
                            exportConfiguration()
                        }
                        Button("Import Configuration…", systemImage: "square.and.arrow.down") {
                            importConfiguration()
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func chooseFolders(for workspaceID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Add Folders"
        panel.prompt = "Add Selected"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { store.addFolders(urls: panel.urls, to: workspaceID) }
    }

    private func chooseFolderLocation(for folderID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Change Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.updateFolderLocation(id: folderID, url: url) }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add Application"
        panel.prompt = "Add Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.addApplication(url: url)
        } catch {
            applicationError = error.localizedDescription
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = "Export Dashboard Configuration"
        panel.nameFieldStringValue = "edge-work-dashboard.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportConfiguration(to: url)
            configurationMessage = "Configuration exported successfully."
        } catch {
            configurationMessage = error.localizedDescription
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Import Dashboard Configuration"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importConfiguration(from: url)
            configurationMessage = "Configuration imported successfully. Review folder paths and application availability on this Mac."
        } catch {
            configurationMessage = error.localizedDescription
        }
    }

    private func settingsForm<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsHeader(title: title, subtitle: subtitle)
            Form { content() }.formStyle(.grouped)
        }
    }

    private func settingsHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func binding<Value: Sendable>(
        get: @escaping @MainActor @Sendable () -> Value,
        set: @escaping @MainActor @Sendable (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }

    private func colorBinding(
        get: @escaping @MainActor @Sendable () -> String,
        set: @escaping @MainActor @Sendable (String) -> Void
    ) -> Binding<Color> {
        Binding(get: { DashboardColor.color(from: get()) }, set: { set(DashboardColor.hex(from: $0)) })
    }
}

private enum PreferencesSection: String, CaseIterable, Identifiable {
    case general, workspaces, applications, terminal, display, configuration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .workspaces: "Workspaces"
        case .applications: "Applications"
        case .terminal: "Terminal"
        case .display: "Display"
        case .configuration: "Configuration"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .workspaces: "rectangle.stack"
        case .applications: "app"
        case .terminal: "terminal"
        case .display: "display"
        case .configuration: "arrow.up.arrow.down.circle"
        }
    }
}
