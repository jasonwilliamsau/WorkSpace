import AppKit
import Foundation
import WebKit

enum DashboardAction: Equatable {
    case showDashboard
    case selectWorkspace(UUID)
    case openFolder(UUID, UUID)
    case openFolderInTerminal(UUID)
    case openFolderRecipe(UUID, UUID)
    case addFolders
    case focusOverlay
    case refresh
    case showPreferences
    case quit
}

private struct DashboardMessage: Decodable {
    let type: String
    let action: String
    let workspace: UUID?
    let folder: UUID?
    let application: UUID?
}

@MainActor
final class DashboardWebViewController: NSViewController, WKScriptMessageHandler {
    var onAction: ((DashboardAction) -> Void)?
    var onReady: (() -> Void)?

    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        configuration.userContentController = controller
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        controller.add(self, name: "edge")
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = webView
        webView.setValue(false, forKey: "drawsBackground")
        guard let (page, resourceRoot) = dashboardPage() else {
            webView.loadHTMLString(
                "<body style='margin:0;background:#080a0f;color:#fff;font:24px -apple-system;padding:40px'>Dashboard resources are missing.</body>",
                baseURL: nil
            )
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: resourceRoot)
    }

    private func dashboardPage() -> (URL, URL)? {
        if let resourceRoot = Bundle.main.resourceURL {
            let dashboardRoot = resourceRoot.appendingPathComponent("Dashboard", isDirectory: true)
            let page = dashboardRoot.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: page.path) {
                return (page, dashboardRoot)
            }
        }

        guard let page = Bundle.module.url(forResource: "index", withExtension: "html"),
              let resourceRoot = Bundle.module.resourceURL else {
            return nil
        }
        return (page, resourceRoot)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "edge",
              JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body),
              let payload = try? JSONDecoder().decode(DashboardMessage.self, from: data),
              payload.type == "action" else {
            return
        }

        switch payload.action {
        case "dashboard.show": onAction?(.showDashboard)
        case "workspace.select":
            if let workspace = payload.workspace { onAction?(.selectWorkspace(workspace)) }
        case "folder.open-app":
            if let folder = payload.folder, let application = payload.application {
                onAction?(.openFolder(folder, application))
            }
        case "folder.open-terminal":
            if let folder = payload.folder { onAction?(.openFolderInTerminal(folder)) }
        case "folder.open-recipe":
            if let folder = payload.folder, let application = payload.application {
                onAction?(.openFolderRecipe(folder, application))
            }
        case "folders.add": onAction?(.addFolders)
        case "overlay.focus": onAction?(.focusOverlay)
        case "status.refresh": onAction?(.refresh)
        case "preferences.show": onAction?(.showPreferences)
        case "app.quit": onAction?(.quit)
        default: break
        }
    }

    func updateDriverHealth(_ health: DriverHealth) {
        evaluate(function: "updateDriverHealth", value: health)
    }

    func updateDisplayMessage(_ message: String) {
        evaluate(function: "updateDisplayMessage", value: ["message": message])
    }

    func updateSystemMetrics(_ metrics: SystemMetrics) {
        evaluate(function: "updateSystemMetrics", value: metrics)
    }

    func updatePreferences(_ preferences: DashboardPreferencesSnapshot) {
        evaluate(function: "updatePreferences", value: preferences)
    }

    func presentActionError(_ message: String) {
        evaluate(function: "presentActionError", value: ["message": message])
    }

    func dismissOverlays() {
        webView.evaluateJavaScript("window.edgeDashboard?.dismissOverlays();")
    }

    private func evaluate<T: Encodable>(function: String, value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.edgeDashboard?.\(function)(\(json));")
    }
}

extension DashboardWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
    }
}
