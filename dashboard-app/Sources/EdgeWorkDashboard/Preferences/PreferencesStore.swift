import AppKit
import Foundation

enum ApplicationConfigurationError: LocalizedError {
    case invalidApplication

    var errorDescription: String? { "The selected item is not a macOS application." }
}

enum ConfigurationTransferError: LocalizedError {
    case invalidConfiguration
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The selected file is not a valid EDGE Work Dashboard configuration."
        case .newerVersion: "This configuration was created by a newer version of EDGE Work Dashboard."
        }
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet {
            guard !isLoading else { return }
            save()
            onChange?(preferences)
        }
    }

    var onChange: ((AppPreferences) -> Void)?

    private let fileURL: URL
    private var isLoading = false

    init(fileURL: URL = PreferencesStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.preferences = Self.load(from: fileURL)
    }

    func addFolders(urls: [URL], to workspaceID: UUID) {
        guard preferences.workspaces.contains(where: { $0.id == workspaceID }) else { return }
        var existingPaths = Set(
            preferences.folders
                .filter { $0.workspaceID == workspaceID }
                .map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }
        )
        let additions = urls.compactMap { url -> FolderPreferences? in
            let standardizedURL = url.standardizedFileURL
            guard existingPaths.insert(standardizedURL.path).inserted else { return nil }
            let bookmark = try? standardizedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let name = standardizedURL.lastPathComponent.isEmpty ? "Folder" : standardizedURL.lastPathComponent
            return FolderPreferences(
                name: name,
                path: standardizedURL.path,
                bookmarkData: bookmark,
                icon: Self.initials(for: name),
                workspaceID: workspaceID
            )
        }
        guard !additions.isEmpty else { return }
        preferences.folders.append(contentsOf: additions)
    }

    func addWorkspace() {
        let number = preferences.workspaces.count + 1
        let workspace = DashboardWorkspacePreferences(
            name: "Workspace \(number)",
            shortLabel: "W\(number)",
            color: "#8D7CFF"
        )
        preferences.workspaces.append(workspace)
    }

    func addApplication(url: URL) throws {
        guard url.pathExtension.lowercased() == "app",
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            throw ApplicationConfigurationError.invalidApplication
        }
        guard !preferences.applications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
        let application = ApplicationPreferences(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url.path,
            bookmarkData: bookmark
        )
        preferences.applications.append(application)
        if preferences.editor.defaultApplicationID == nil {
            preferences.editor.defaultApplicationID = application.id
        }
    }

    func removeApplication(id: UUID) {
        guard let application = preferences.applications.first(where: { $0.id == id }),
              !application.isBuiltIn else { return }
        preferences.applications.removeAll { $0.id == id }
        if preferences.editor.defaultApplicationID == id {
            preferences.editor.defaultApplicationID = preferences.applications.first(where: \.isEnabled)?.id
        }
    }

    func moveApplication(id: UUID, direction: Int) {
        guard let index = preferences.applications.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard preferences.applications.indices.contains(destination) else { return }
        preferences.applications.swapAt(index, destination)
    }

    func setApplicationEnabled(id: UUID, enabled: Bool) {
        guard let index = preferences.applications.firstIndex(where: { $0.id == id }) else { return }
        preferences.applications[index].isEnabled = enabled
        if !enabled, preferences.editor.defaultApplicationID == id {
            preferences.editor.defaultApplicationID = preferences.applications.first(where: {
                $0.id != id && $0.isEnabled
            })?.id
        } else if enabled, preferences.editor.defaultApplicationID == nil {
            preferences.editor.defaultApplicationID = id
        }
    }

    func setDefaultApplication(id: UUID) {
        guard preferences.applications.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        preferences.editor.defaultApplicationID = id
    }

    func resolvedURL(for application: ApplicationPreferences) -> URL? {
        if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) {
            return installed
        }
        if let bookmarkData = application.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        if let path = application.path { return URL(fileURLWithPath: path) }
        return nil
    }

    func exportConfiguration(to url: URL) throws {
        var portable = preferences
        portable.schemaVersion = AppPreferences.currentSchemaVersion
        portable.display.targetDisplayUUID = nil
        portable.display.targetDisplayName = nil
        for index in portable.folders.indices {
            portable.folders[index].bookmarkData = nil
        }
        for index in portable.applications.indices {
            portable.applications[index].bookmarkData = nil
            portable.applications[index].path = nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(portable).write(to: url, options: .atomic)
    }

    func importConfiguration(from url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              var imported = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            throw ConfigurationTransferError.invalidConfiguration
        }
        guard imported.schemaVersion <= AppPreferences.currentSchemaVersion else {
            throw ConfigurationTransferError.newerVersion
        }
        imported = Self.normalized(imported)
        imported.general.hasCompletedSetup = true
        preferences = imported
    }

    func removeWorkspace(id: UUID) {
        guard preferences.workspaces.count > 1,
              let index = preferences.workspaces.firstIndex(where: { $0.id == id }) else { return }
        preferences.workspaces.remove(at: index)
        guard let replacementID = preferences.workspaces.first?.id else { return }
        for folderIndex in preferences.folders.indices where preferences.folders[folderIndex].workspaceID == id {
            preferences.folders[folderIndex].workspaceID = replacementID
        }
        if preferences.general.startWorkspace == id.uuidString {
            preferences.general.startWorkspace = replacementID.uuidString
        }
    }

    func moveWorkspace(id: UUID, direction: Int) {
        guard let index = preferences.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard preferences.workspaces.indices.contains(destination) else { return }
        preferences.workspaces.swapAt(index, destination)
    }

    func removeFolder(id: UUID) {
        preferences.folders.removeAll { $0.id == id }
    }

    func moveFolder(id: UUID, direction: Int) {
        guard let index = preferences.folders.firstIndex(where: { $0.id == id }),
              let workspaceID = preferences.folders[index].workspaceID else { return }
        let siblingIndices = preferences.folders.indices.filter { preferences.folders[$0].workspaceID == workspaceID }
        guard let siblingPosition = siblingIndices.firstIndex(of: index) else { return }
        let destinationPosition = siblingPosition + direction
        guard siblingIndices.indices.contains(destinationPosition) else { return }
        preferences.folders.swapAt(index, siblingIndices[destinationPosition])
    }

    func effectiveApplicationIDs(for folder: FolderPreferences) -> [UUID] {
        let enabledIDs = preferences.applications.filter(\.isEnabled).map(\.id)
        return (folder.applicationIDs ?? enabledIDs).filter(enabledIDs.contains)
    }

    func setFolderApplication(folderID: UUID, applicationID: UUID, enabled: Bool) {
        guard let folderIndex = preferences.folders.firstIndex(where: { $0.id == folderID }),
              preferences.applications.contains(where: { $0.id == applicationID && $0.isEnabled }) else { return }
        var applicationIDs = effectiveApplicationIDs(for: preferences.folders[folderIndex])
        if enabled {
            if !applicationIDs.contains(applicationID) { applicationIDs.append(applicationID) }
        } else {
            applicationIDs.removeAll { $0 == applicationID }
        }
        preferences.folders[folderIndex].applicationIDs = applicationIDs
        if let defaultID = preferences.folders[folderIndex].defaultApplicationID,
           !applicationIDs.contains(defaultID) {
            preferences.folders[folderIndex].defaultApplicationID = applicationIDs.first
        }
    }

    func moveFolderApplication(folderID: UUID, applicationID: UUID, direction: Int) {
        guard let folderIndex = preferences.folders.firstIndex(where: { $0.id == folderID }) else { return }
        var applicationIDs = effectiveApplicationIDs(for: preferences.folders[folderIndex])
        guard let index = applicationIDs.firstIndex(of: applicationID) else { return }
        let destination = index + direction
        guard applicationIDs.indices.contains(destination) else { return }
        applicationIDs.swapAt(index, destination)
        preferences.folders[folderIndex].applicationIDs = applicationIDs
    }

    func setFolderDefaultApplication(folderID: UUID, applicationID: UUID?) {
        guard let folderIndex = preferences.folders.firstIndex(where: { $0.id == folderID }) else { return }
        if let applicationID,
           !effectiveApplicationIDs(for: preferences.folders[folderIndex]).contains(applicationID) { return }
        preferences.folders[folderIndex].defaultApplicationID = applicationID
    }

    func resetFolderApplications(folderID: UUID) {
        guard let folderIndex = preferences.folders.firstIndex(where: { $0.id == folderID }) else { return }
        preferences.folders[folderIndex].applicationIDs = nil
        preferences.folders[folderIndex].defaultApplicationID = nil
    }

    func updateFolderLocation(id: UUID, url: URL) {
        guard let index = preferences.folders.firstIndex(where: { $0.id == id }) else { return }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        preferences.folders[index].path = url.standardizedFileURL.path
        preferences.folders[index].bookmarkData = bookmark
    }

    func resolvedURL(for folder: FolderPreferences) -> URL {
        guard let bookmarkData = folder.bookmarkData else {
            return URL(fileURLWithPath: folder.path)
        }

        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            if stale { refreshBookmark(for: folder.id, url: url) }
            return url
        }
        return URL(fileURLWithPath: folder.path)
    }

    private func refreshBookmark(for folderID: UUID, url: URL) {
        guard let index = preferences.folders.firstIndex(where: { $0.id == folderID }),
              let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
              ) else { return }
        isLoading = true
        preferences.folders[index].bookmarkData = bookmark
        isLoading = false
        save()
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("EDGE Work Dashboard could not save preferences: %@", error.localizedDescription)
        }
    }

    private static func load(from url: URL) -> AppPreferences {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data),
              decoded.schemaVersion <= AppPreferences.currentSchemaVersion else {
            return .defaults
        }
        return normalized(decoded)
    }

    private static func normalized(_ source: AppPreferences) -> AppPreferences {
        var decoded = source
        if decoded.workspaces.isEmpty { decoded.workspaces = [.development] }
        if !decoded.applications.contains(where: { $0.id == ApplicationPreferences.finderID }) {
            decoded.applications.append(ApplicationPreferences.defaultApplications[0])
        }
        if let defaultID = decoded.editor.defaultApplicationID,
           !decoded.applications.contains(where: { $0.id == defaultID && $0.isEnabled }) {
            decoded.editor.defaultApplicationID = decoded.applications.first(where: \.isEnabled)?.id
        }
        let fallbackID = decoded.workspaces[0].id
        for index in decoded.folders.indices {
            if decoded.folders[index].workspaceID == nil ||
                !decoded.workspaces.contains(where: { $0.id == decoded.folders[index].workspaceID }) {
                decoded.folders[index].workspaceID = fallbackID
            }
            decoded.folders[index].color = normalizedColor(decoded.folders[index].color)
        }
        decoded.schemaVersion = AppPreferences.currentSchemaVersion
        if UUID(uuidString: decoded.general.startWorkspace) == nil ||
            !decoded.workspaces.contains(where: { $0.id.uuidString == decoded.general.startWorkspace }) {
            decoded.general.startWorkspace = fallbackID.uuidString
        }
        return decoded
    }

    private static func normalizedColor(_ value: String) -> String {
        switch value.lowercased() {
        case "violet": "#8D7CFF"
        case "blue": "#72A6FF"
        case "amber": "#F0BA5B"
        case "green": "#65DDA2"
        default: value
        }
    }

    nonisolated private static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EDGE Work Dashboard", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    private static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let value = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return String((value.isEmpty ? "FD" : value).uppercased().prefix(3))
    }
}
