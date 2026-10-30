import Foundation

struct DriverHealth: Codable, Equatable {
    let state: String
    let message: String
    let routingOpen: Bool
    let reports: UInt64
    let updatedAt: Date
}

private struct DriverStatusPayload: Decodable {
    struct Controller: Decodable {
        let state: String
        let reason: String
        let receivedReports: UInt64
    }

    let controllers: [Controller]
    let routingGateOpen: Bool
    let heartbeatFresh: Bool
}

final class DriverHealthProvider {
    var onUpdate: ((DriverHealth) -> Void)?

    private let queue = DispatchQueue(label: "com.nocreativity.EdgeWorkDashboard.driver-health")
    private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(3), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in self?.readStatus() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    func refreshNow() {
        queue.async { [weak self] in self?.readStatus() }
    }

    private func readStatus() {
        let binary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacXeneonEdgeTouchDriver/bin/MacXeneonEdgeTouchDriver")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            publish(DriverHealth(
                state: "missing",
                message: "Touch driver is not installed",
                routingOpen: false,
                reports: 0,
                updatedAt: Date()
            ))
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = binary
        process.arguments = ["status"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let payload = try JSONDecoder().decode(DriverStatusPayload.self, from: data)
            let controller = payload.controllers.first
            publish(DriverHealth(
                state: controller?.state ?? "waiting",
                message: controller?.reason ?? "No touch controller detected",
                routingOpen: payload.routingGateOpen && payload.heartbeatFresh,
                reports: controller?.receivedReports ?? 0,
                updatedAt: Date()
            ))
        } catch {
            publish(DriverHealth(
                state: "offline",
                message: "Touch driver is not reachable",
                routingOpen: false,
                reports: 0,
                updatedAt: Date()
            ))
        }
    }

    private func publish(_ health: DriverHealth) {
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(health) }
    }
}
