import Foundation
@testable import EdgeWorkDashboard
import XCTest

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testFolderChangesPersistAndRetainOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("First Folder", isDirectory: true)
        let secondURL = root.appendingPathComponent("second-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let store = PreferencesStore(fileURL: preferencesURL)
        let workspaceID = try XCTUnwrap(store.preferences.workspaces.first?.id)
        store.addFolders(urls: [firstURL, secondURL], to: workspaceID)
        let secondID = try XCTUnwrap(store.preferences.folders.last?.id)
        store.moveFolder(id: secondID, direction: -1)
        let replacementURL = root.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
        store.updateFolderLocation(id: secondID, url: replacementURL)
        store.preferences.general.dashboardTitle = "Studio dashboard"

        let reloaded = PreferencesStore(fileURL: preferencesURL)
        XCTAssertEqual(reloaded.preferences.general.dashboardTitle, "Studio dashboard")
        XCTAssertEqual(reloaded.preferences.folders.map(\.name), ["second-folder", "First Folder"])
        XCTAssertEqual(reloaded.preferences.folders.first?.path, replacementURL.path)
    }

    func testMultipleFoldersAreAddedToRequestedWorkspaceWithoutDuplicates() throws {
        let preferencesURL = temporaryPreferencesURL()
        defer { try? FileManager.default.removeItem(at: preferencesURL.deletingLastPathComponent()) }
        let store = PreferencesStore(fileURL: preferencesURL)
        store.addWorkspace()
        let workspaceID = try XCTUnwrap(store.preferences.workspaces.last?.id)
        let first = URL(fileURLWithPath: "/tmp/first-folder")
        let second = URL(fileURLWithPath: "/tmp/second-folder")

        store.addFolders(urls: [first, second, first], to: workspaceID)

        XCTAssertEqual(store.preferences.folders.map(\.name), ["first-folder", "second-folder"])
        XCTAssertEqual(Set(store.preferences.folders.compactMap(\.workspaceID)), [workspaceID])
        XCTAssertEqual(PreferencesStore(fileURL: preferencesURL).preferences.folders.count, 2)
    }

    func testSameFolderCanBelongToMoreThanOneWorkspace() throws {
        let preferencesURL = temporaryPreferencesURL()
        defer { try? FileManager.default.removeItem(at: preferencesURL.deletingLastPathComponent()) }
        let store = PreferencesStore(fileURL: preferencesURL)
        let firstWorkspaceID = try XCTUnwrap(store.preferences.workspaces.first?.id)
        store.addWorkspace()
        let secondWorkspaceID = try XCTUnwrap(store.preferences.workspaces.last?.id)
        let sharedFolder = URL(fileURLWithPath: "/tmp/shared-folder")

        store.addFolders(urls: [sharedFolder], to: firstWorkspaceID)
        store.addFolders(urls: [sharedFolder], to: secondWorkspaceID)
        store.addFolders(urls: [sharedFolder], to: secondWorkspaceID)

        XCTAssertEqual(store.preferences.folders.count, 2)
        XCTAssertEqual(Set(store.preferences.folders.compactMap(\.workspaceID)), [firstWorkspaceID, secondWorkspaceID])
        XCTAssertEqual(Set(store.preferences.folders.map(\.path)), [sharedFolder.path])
    }

    func testFolderApplicationOverridesCanBeConfiguredAndReset() throws {
        let preferencesURL = temporaryPreferencesURL()
        defer { try? FileManager.default.removeItem(at: preferencesURL.deletingLastPathComponent()) }
        let store = PreferencesStore(fileURL: preferencesURL)
        store.preferences.applications = ApplicationPreferences.knownApplications
        let workspaceID = try XCTUnwrap(store.preferences.workspaces.first?.id)
        store.addFolders(urls: [URL(fileURLWithPath: "/tmp/action-folder")], to: workspaceID)
        let folderID = try XCTUnwrap(store.preferences.folders.first?.id)

        store.setFolderApplication(
            folderID: folderID,
            applicationID: ApplicationPreferences.xcodeID,
            enabled: false
        )
        store.moveFolderApplication(
            folderID: folderID,
            applicationID: ApplicationPreferences.visualStudioCodeID,
            direction: -1
        )
        store.setFolderDefaultApplication(
            folderID: folderID,
            applicationID: ApplicationPreferences.visualStudioCodeID
        )
        store.preferences.folders[0].primaryAction = .defaultApplicationAndTerminal

        let configured = store.preferences.folders[0]
        XCTAssertFalse(store.effectiveApplicationIDs(for: configured).contains(ApplicationPreferences.xcodeID))
        XCTAssertEqual(configured.defaultApplicationID, ApplicationPreferences.visualStudioCodeID)
        XCTAssertEqual(configured.primaryAction, .defaultApplicationAndTerminal)

        let snapshot = DashboardPreferencesSnapshot(preferences: store.preferences)
        XCTAssertEqual(snapshot.folders[0].defaultApplicationID, ApplicationPreferences.visualStudioCodeID)
        XCTAssertEqual(snapshot.folders[0].primaryAction, .defaultApplicationAndTerminal)

        store.resetFolderApplications(folderID: folderID)
        XCTAssertNil(store.preferences.folders[0].applicationIDs)
        XCTAssertNil(store.preferences.folders[0].defaultApplicationID)
    }

    func testWorkspacesCanBeAddedReorderedAndDeleted() throws {
        let preferencesURL = temporaryPreferencesURL()
        defer { try? FileManager.default.removeItem(at: preferencesURL.deletingLastPathComponent()) }
        let store = PreferencesStore(fileURL: preferencesURL)
        let originalID = try XCTUnwrap(store.preferences.workspaces.first?.id)
        store.addWorkspace()
        let newID = try XCTUnwrap(store.preferences.workspaces.last?.id)
        store.preferences.workspaces[1].name = "Infrastructure"
        store.preferences.workspaces[1].shortLabel = "INF"
        store.preferences.workspaces[1].color = "#12AB34"
        store.moveWorkspace(id: newID, direction: -1)
        store.addFolders(urls: [URL(fileURLWithPath: "/tmp/workspace-folder")], to: originalID)
        store.removeWorkspace(id: originalID)

        XCTAssertEqual(store.preferences.workspaces.map(\.id), [newID])
        XCTAssertEqual(store.preferences.workspaces[0].color, "#12AB34")
        XCTAssertEqual(store.preferences.folders[0].workspaceID, newID)

        let reloaded = PreferencesStore(fileURL: preferencesURL)
        XCTAssertEqual(reloaded.preferences.workspaces.map(\.name), ["Infrastructure"])
        XCTAssertEqual(reloaded.preferences.folders[0].workspaceID, newID)
    }

    func testVersionTwoProfilesAndWorkspacesMigrateToWorkspacesAndFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspaceID = "70F7D40B-F5EC-46CF-8BA6-FD07525C6772"
        let legacy = """
        {
          "schemaVersion": 2,
          "general": {"dashboardTitle":"Legacy","startProfile":"\(workspaceID)"},
          "display": {},
          "editor": {"provider":"finder"},
          "terminal": {"provider":"macOSTerminal","layout":"windows","sessionCount":2,"reuseExistingSession":true},
          "profiles": [{"id":"\(workspaceID)","name":"Clients","shortLabel":"CLI","color":"#123456"}],
          "workspaces": [{
            "id":"E4999001-727E-4BA5-937D-8A21C406A181",
            "name":"Existing Project","path":"/tmp/existing","icon":"EP",
            "color":"violet","terminalEnabled":true,"profileID":"\(workspaceID)"
          }]
        }
        """
        try Data(legacy.utf8).write(to: preferencesURL)

        let migrated = PreferencesStore(fileURL: preferencesURL).preferences

        XCTAssertEqual(migrated.schemaVersion, AppPreferences.currentSchemaVersion)
        XCTAssertEqual(migrated.workspaces.map(\.name), ["Clients"])
        XCTAssertEqual(migrated.folders.map(\.name), ["Existing Project"])
        XCTAssertEqual(migrated.folders[0].workspaceID?.uuidString, workspaceID)
        XCTAssertEqual(migrated.folders[0].color, "#8D7CFF")
        XCTAssertEqual(migrated.general.startWorkspace, workspaceID)
        XCTAssertEqual(migrated.editor.defaultApplicationID, ApplicationPreferences.finderID)
        XCTAssertTrue(migrated.general.hasCompletedSetup)
    }

    func testNewInstallRequiresSetup() {
        XCTAssertFalse(AppPreferences.defaults.general.hasCompletedSetup)
        XCTAssertEqual(AppPreferences.defaults.applications.map(\.id), [ApplicationPreferences.finderID])
        XCTAssertEqual(AppPreferences.defaults.editor.defaultApplicationID, ApplicationPreferences.finderID)
    }

    func testConfigurationExportAndImportIsPortable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source/preferences.json")
        let destinationURL = root.appendingPathComponent("destination/preferences.json")
        let exportURL = root.appendingPathComponent("backup.json")
        let store = PreferencesStore(fileURL: sourceURL)
        let workspaceID = try XCTUnwrap(store.preferences.workspaces.first?.id)
        store.addFolders(urls: [URL(fileURLWithPath: "/tmp/exported-folder")], to: workspaceID)
        store.preferences.general.dashboardTitle = "Portable dashboard"
        store.preferences.display.targetDisplayUUID = "machine-specific-display"
        try store.exportConfiguration(to: exportURL)

        let exportedData = try Data(contentsOf: exportURL)
        let exported = try JSONDecoder().decode(AppPreferences.self, from: exportedData)
        XCTAssertNil(exported.display.targetDisplayUUID)
        XCTAssertTrue(exported.folders.allSatisfy { $0.bookmarkData == nil })
        XCTAssertTrue(exported.applications.allSatisfy { $0.bookmarkData == nil && $0.path == nil })

        let importedStore = PreferencesStore(fileURL: destinationURL)
        try importedStore.importConfiguration(from: exportURL)
        XCTAssertEqual(importedStore.preferences.general.dashboardTitle, "Portable dashboard")
        XCTAssertEqual(importedStore.preferences.folders.map(\.path), ["/tmp/exported-folder"])
        XCTAssertTrue(importedStore.preferences.general.hasCompletedSetup)
    }

    func testDashboardOnlyOffersAvailableApplicationsAndMarksDefault() {
        var preferences = AppPreferences.defaults
        preferences.applications = ApplicationPreferences.knownApplications
        preferences.editor.defaultApplicationID = ApplicationPreferences.visualStudioCodeID

        let snapshot = DashboardPreferencesSnapshot(
            preferences: preferences,
            applicationIcon: { "icon://\($0.id)" },
            applicationAvailable: { $0.id != ApplicationPreferences.xcodeID }
        )

        XCTAssertEqual(
            snapshot.applications.map(\.id),
            [
                ApplicationPreferences.cursorID,
                ApplicationPreferences.visualStudioCodeID,
                ApplicationPreferences.finderID
            ]
        )
        XCTAssertEqual(snapshot.applications.first(where: \.isDefault)?.id, ApplicationPreferences.visualStudioCodeID)
        XCTAssertFalse(snapshot.applications.contains(where: { $0.id == ApplicationPreferences.xcodeID }))
        XCTAssertEqual(snapshot.applications.first?.iconDataURL, "icon://\(ApplicationPreferences.cursorID)")
    }

    func testApplicationsCanBeAddedManagedAndRemoved() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let appURL = root.appendingPathComponent("Nova.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.Nova",
            "CFBundleName": "Nova",
            "CFBundlePackageType": "APPL"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        let store = PreferencesStore(fileURL: preferencesURL)

        try store.addApplication(url: appURL)
        let application = try XCTUnwrap(store.preferences.applications.last)
        store.setDefaultApplication(id: application.id)
        store.setApplicationEnabled(id: application.id, enabled: false)

        XCTAssertEqual(store.preferences.editor.defaultApplicationID, ApplicationPreferences.finderID)
        store.setApplicationEnabled(id: application.id, enabled: true)
        store.setDefaultApplication(id: application.id)
        XCTAssertEqual(store.preferences.editor.defaultApplicationID, application.id)
        store.removeApplication(id: application.id)
        XCTAssertFalse(store.preferences.applications.contains(where: { $0.id == application.id }))
        XCTAssertEqual(store.preferences.editor.defaultApplicationID, ApplicationPreferences.finderID)
    }

    private func temporaryPreferencesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-dashboard-tests-\(UUID().uuidString)/preferences.json")
    }
}
