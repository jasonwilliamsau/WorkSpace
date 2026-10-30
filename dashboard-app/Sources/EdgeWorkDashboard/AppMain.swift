import AppKit
import Foundation

@main
enum EdgeWorkDashboardMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = DashboardApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

final class DashboardApplicationDelegate: NSObject, NSApplicationDelegate {
    private var dashboard: EdgeDashboardApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dashboard = EdgeDashboardApplication()
        self.dashboard = dashboard
        dashboard.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dashboard?.stop()
    }
}
