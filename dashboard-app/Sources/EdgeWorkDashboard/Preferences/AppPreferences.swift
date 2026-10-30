import Foundation

struct AppPreferences: Codable, Equatable {
    static let currentSchemaVersion = 6
    static let defaultWorkspaceID = UUID(uuidString: "89EE1702-ED2B-4B25-8829-5D24D826B774")!

    var schemaVersion: Int
    var general: GeneralPreferences
    var display: DisplayPreferences
    var editor: EditorPreferences
    var terminal: TerminalPreferences
    var applications: [ApplicationPreferences]
    var workspaces: [DashboardWorkspacePreferences]
    var folders: [FolderPreferences]

    init(
        schemaVersion: Int,
        general: GeneralPreferences,
        display: DisplayPreferences,
        editor: EditorPreferences,
        terminal: TerminalPreferences,
        applications: [ApplicationPreferences],
        workspaces: [DashboardWorkspacePreferences],
        folders: [FolderPreferences]
    ) {
        self.schemaVersion = schemaVersion
        self.general = general
        self.display = display
        self.editor = editor
        self.terminal = terminal
        self.applications = applications
        self.workspaces = workspaces
        self.folders = folders
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, general, display, editor, terminal, applications
        case profiles // Version 1-2 top-level workspaces.
        case workspaces
        case folders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        general = try container.decodeIfPresent(GeneralPreferences.self, forKey: .general) ?? GeneralPreferences()
        display = try container.decodeIfPresent(DisplayPreferences.self, forKey: .display) ?? DisplayPreferences()
        editor = try container.decodeIfPresent(EditorPreferences.self, forKey: .editor) ?? EditorPreferences()
        terminal = try container.decodeIfPresent(TerminalPreferences.self, forKey: .terminal) ?? TerminalPreferences()
        if schemaVersion < 3 {
            workspaces = try container.decodeIfPresent([DashboardWorkspacePreferences].self, forKey: .profiles)
                ?? [.development]
            folders = try container.decodeIfPresent([FolderPreferences].self, forKey: .workspaces) ?? []
        } else {
            workspaces = try container.decodeIfPresent([DashboardWorkspacePreferences].self, forKey: .workspaces)
                ?? [.development]
            folders = try container.decodeIfPresent([FolderPreferences].self, forKey: .folders) ?? []
        }
        if schemaVersion < 4 {
            applications = ApplicationPreferences.migrationApplications(for: editor.legacyProvider)
            editor.defaultApplicationID = applications.first(where: {
                $0.legacyProvider == editor.legacyProvider
            })?.id ?? ApplicationPreferences.finderID
        } else {
            applications = try container.decodeIfPresent([ApplicationPreferences].self, forKey: .applications)
                ?? ApplicationPreferences.defaultApplications
        }
        if schemaVersion < 5 {
            general.hasCompletedSetup = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(general, forKey: .general)
        try container.encode(display, forKey: .display)
        try container.encode(editor, forKey: .editor)
        try container.encode(terminal, forKey: .terminal)
        try container.encode(applications, forKey: .applications)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encode(folders, forKey: .folders)
    }

    static let defaults = AppPreferences(
        schemaVersion: currentSchemaVersion,
        general: GeneralPreferences(),
        display: DisplayPreferences(),
        editor: EditorPreferences(),
        terminal: TerminalPreferences(),
        applications: ApplicationPreferences.defaultApplications,
        workspaces: [.development],
        folders: []
    )
}

struct GeneralPreferences: Codable, Equatable {
    var dashboardTitle: String
    var startWorkspace: String
    var hasCompletedSetup: Bool

    init(
        dashboardTitle: String = "Work command centre",
        startWorkspace: String = AppPreferences.defaultWorkspaceID.uuidString,
        hasCompletedSetup: Bool = false
    ) {
        self.dashboardTitle = dashboardTitle
        self.startWorkspace = startWorkspace
        self.hasCompletedSetup = hasCompletedSetup
    }

    private enum CodingKeys: String, CodingKey {
        case dashboardTitle, startWorkspace, startProfile, hasCompletedSetup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dashboardTitle = try container.decodeIfPresent(String.self, forKey: .dashboardTitle) ?? "Work command centre"
        startWorkspace = try container.decodeIfPresent(String.self, forKey: .startWorkspace)
            ?? container.decodeIfPresent(String.self, forKey: .startProfile)
            ?? AppPreferences.defaultWorkspaceID.uuidString
        hasCompletedSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dashboardTitle, forKey: .dashboardTitle)
        try container.encode(startWorkspace, forKey: .startWorkspace)
        try container.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
    }
}

struct DashboardWorkspacePreferences: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var shortLabel: String
    var color: String

    init(id: UUID = UUID(), name: String, shortLabel: String, color: String) {
        self.id = id
        self.name = name
        self.shortLabel = shortLabel
        self.color = color
    }

    static let development = DashboardWorkspacePreferences(
        id: AppPreferences.defaultWorkspaceID,
        name: "Development",
        shortLabel: "DEV",
        color: "#8D7CFF"
    )
}

struct DisplayPreferences: Codable, Equatable {
    var targetDisplayUUID: String?
    var targetDisplayName: String?
}

enum EditorProviderID: String, Codable, CaseIterable, Identifiable {
    case cursor
    case visualStudioCode
    case xcode
    case finder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .visualStudioCode: "Visual Studio Code"
        case .xcode: "Xcode"
        case .finder: "Finder"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .visualStudioCode: "com.microsoft.VSCode"
        case .xcode: "com.apple.dt.Xcode"
        case .finder: "com.apple.finder"
        }
    }
}

struct EditorPreferences: Codable, Equatable {
    var defaultApplicationID: UUID?
    var legacyProvider: EditorProviderID?

    init(
        defaultApplicationID: UUID? = ApplicationPreferences.finderID,
        legacyProvider: EditorProviderID? = .finder
    ) {
        self.defaultApplicationID = defaultApplicationID
        self.legacyProvider = legacyProvider
    }

    private enum CodingKeys: String, CodingKey { case defaultApplicationID, provider }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultApplicationID = try container.decodeIfPresent(UUID.self, forKey: .defaultApplicationID)
        legacyProvider = try container.decodeIfPresent(EditorProviderID.self, forKey: .provider)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(defaultApplicationID, forKey: .defaultApplicationID)
    }
}

struct ApplicationPreferences: Codable, Equatable, Identifiable {
    static let cursorID = UUID(uuidString: "2E7F912E-AE35-435B-B77B-D569D076C15A")!
    static let visualStudioCodeID = UUID(uuidString: "660CB8AF-D5F5-429A-BC7A-C591FE55B657")!
    static let xcodeID = UUID(uuidString: "73A97FC1-5899-4EAB-A86D-B36CAC575477")!
    static let finderID = UUID(uuidString: "FB8D0A42-D47C-42A5-9669-0A7EFC8D0A97")!

    let id: UUID
    var name: String
    var bundleIdentifier: String
    var path: String?
    var bookmarkData: Data?
    var isEnabled: Bool
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        path: String? = nil,
        bookmarkData: Data? = nil,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.bookmarkData = bookmarkData
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    var legacyProvider: EditorProviderID? {
        EditorProviderID.allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }

    static let knownApplications = [
        ApplicationPreferences(id: cursorID, name: "Cursor", bundleIdentifier: EditorProviderID.cursor.bundleIdentifier),
        ApplicationPreferences(
            id: visualStudioCodeID,
            name: "Visual Studio Code",
            bundleIdentifier: EditorProviderID.visualStudioCode.bundleIdentifier
        ),
        ApplicationPreferences(id: xcodeID, name: "Xcode", bundleIdentifier: EditorProviderID.xcode.bundleIdentifier),
        ApplicationPreferences(
            id: finderID,
            name: "Finder",
            bundleIdentifier: EditorProviderID.finder.bundleIdentifier,
            isBuiltIn: true
        )
    ]

    static let defaultApplications = [knownApplications.last!]

    static func migrationApplications(for provider: EditorProviderID?) -> [ApplicationPreferences] {
        guard let provider,
              let selected = knownApplications.first(where: { $0.legacyProvider == provider }),
              selected.id != finderID else { return defaultApplications }
        return [selected, knownApplications.last!]
    }
}

enum TerminalProviderID: String, Codable, CaseIterable, Identifiable {
    case iTerm2
    case macOSTerminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iTerm2: "iTerm2"
        case .macOSTerminal: "macOS Terminal"
        }
    }
}

enum TerminalLayout: String, Codable, CaseIterable, Identifiable {
    case tabs
    case splitVertically
    case splitHorizontally
    case windows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tabs: "Tabs"
        case .splitVertically: "Vertical panes"
        case .splitHorizontally: "Horizontal panes"
        case .windows: "Separate windows"
        }
    }
}

struct TerminalPreferences: Codable, Equatable {
    var provider: TerminalProviderID = .macOSTerminal
    var layout: TerminalLayout = .windows
    var sessionCount = 2
    var reuseExistingSession = true
}

struct FolderPreferences: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?
    var icon: String
    var color: String
    var workspaceID: UUID?
    var applicationIDs: [UUID]?
    var defaultApplicationID: UUID?
    var primaryAction: FolderPrimaryAction

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmarkData: Data?,
        icon: String,
        color: String = "#8D7CFF",
        workspaceID: UUID? = nil,
        applicationIDs: [UUID]? = nil,
        defaultApplicationID: UUID? = nil,
        primaryAction: FolderPrimaryAction = .showMenu
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.icon = icon
        self.color = color
        self.workspaceID = workspaceID
        self.applicationIDs = applicationIDs
        self.defaultApplicationID = defaultApplicationID
        self.primaryAction = primaryAction
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, bookmarkData, icon, color, terminalEnabled, workspaceID, profileID
        case applicationIDs, defaultApplicationID, primaryAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID)
            ?? container.decodeIfPresent(UUID.self, forKey: .profileID)
        applicationIDs = try container.decodeIfPresent([UUID].self, forKey: .applicationIDs)
        defaultApplicationID = try container.decodeIfPresent(UUID.self, forKey: .defaultApplicationID)
        primaryAction = try container.decodeIfPresent(FolderPrimaryAction.self, forKey: .primaryAction) ?? .showMenu
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(applicationIDs, forKey: .applicationIDs)
        try container.encodeIfPresent(defaultApplicationID, forKey: .defaultApplicationID)
        try container.encode(primaryAction, forKey: .primaryAction)
    }
}

enum FolderPrimaryAction: String, Codable, CaseIterable, Identifiable {
    case showMenu
    case defaultApplication
    case terminal
    case defaultApplicationAndTerminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .showMenu: "Show options"
        case .defaultApplication: "Open default application"
        case .terminal: "Open terminal"
        case .defaultApplicationAndTerminal: "Open default application + terminal"
        }
    }
}

struct DashboardPreferencesSnapshot: Codable, Equatable {
    struct Application: Codable, Equatable {
        let id: UUID
        let name: String
        let isDefault: Bool
        let isAvailable: Bool
        let iconDataURL: String?
    }

    struct Workspace: Codable, Equatable {
        let id: UUID
        let name: String
        let shortLabel: String
        let color: String
    }

    struct Folder: Codable, Equatable {
        let id: UUID
        let name: String
        let path: String
        let icon: String
        let color: String
        let workspaceID: UUID
        let applicationIDs: [UUID]
        let defaultApplicationID: UUID?
        let primaryAction: FolderPrimaryAction
    }

    let dashboardTitle: String
    let startWorkspace: UUID
    let editorName: String
    let terminalName: String
    let applications: [Application]
    let workspaces: [Workspace]
    let folders: [Folder]

    init(
        preferences: AppPreferences,
        applicationIcon: (ApplicationPreferences) -> String? = { _ in nil },
        applicationAvailable: (ApplicationPreferences) -> Bool = { _ in true }
    ) {
        dashboardTitle = preferences.general.dashboardTitle
        let fallbackWorkspace = preferences.workspaces.first?.id ?? AppPreferences.defaultWorkspaceID
        startWorkspace = UUID(uuidString: preferences.general.startWorkspace) ?? fallbackWorkspace
        terminalName = preferences.terminal.provider.displayName
        let availableApplications = preferences.applications.filter {
            $0.isEnabled && applicationAvailable($0)
        }
        let availableApplicationIDs = availableApplications.map(\.id)
        let effectiveDefaultApplicationID = preferences.editor.defaultApplicationID.flatMap {
            availableApplicationIDs.contains($0) ? $0 : nil
        } ?? availableApplicationIDs.first
        editorName = availableApplications.first(where: {
            $0.id == effectiveDefaultApplicationID
        })?.name ?? "Choose an application"
        applications = availableApplications.map {
            Application(
                id: $0.id,
                name: $0.name,
                isDefault: $0.id == effectiveDefaultApplicationID,
                isAvailable: true,
                iconDataURL: applicationIcon($0)
            )
        }
        workspaces = preferences.workspaces.map {
            Workspace(id: $0.id, name: $0.name, shortLabel: $0.shortLabel, color: $0.color)
        }
        folders = preferences.folders.map {
            let applicationIDs = ($0.applicationIDs ?? availableApplicationIDs)
                .filter(availableApplicationIDs.contains)
            let preferredDefault = $0.defaultApplicationID ?? effectiveDefaultApplicationID
            let defaultApplicationID = preferredDefault.flatMap { applicationIDs.contains($0) ? $0 : nil }
                ?? applicationIDs.first
            return Folder(
                id: $0.id,
                name: $0.name,
                path: $0.path,
                icon: $0.icon,
                color: $0.color,
                workspaceID: $0.workspaceID ?? fallbackWorkspace,
                applicationIDs: applicationIDs,
                defaultApplicationID: defaultApplicationID,
                primaryAction: $0.primaryAction
            )
        }
    }
}
