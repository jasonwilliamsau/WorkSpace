import Darwin.Mach
import Foundation

struct SystemMetrics: Codable, Equatable {
    let cpuPercent: Int
    let memoryPercent: Int
    let memoryDetail: String
    let uptime: String
}

@MainActor
final class SystemMetricsProvider {
    var onUpdate: ((SystemMetrics) -> Void)?

    private var timer: Timer?
    private var previousCPUTicks: CPUTicks?

    func start() {
        stop()
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func publish() {
        let cpuPercent = sampleCPUPercent()
        let memory = sampleMemory()
        onUpdate?(SystemMetrics(
            cpuPercent: cpuPercent,
            memoryPercent: memory.percent,
            memoryDetail: memory.detail,
            uptime: Self.formattedUptime(ProcessInfo.processInfo.systemUptime)
        ))
    }

    private func sampleCPUPercent() -> Int {
        guard let current = CPUTicks.current() else { return 0 }
        defer { previousCPUTicks = current }
        guard let previousCPUTicks else { return 0 }
        let busy = current.busy >= previousCPUTicks.busy ? current.busy - previousCPUTicks.busy : 0
        let total = current.total >= previousCPUTicks.total ? current.total - previousCPUTicks.total : 0
        guard total > 0 else { return 0 }
        return min(max(Int((Double(busy) / Double(total) * 100).rounded()), 0), 100)
    }

    private func sampleMemory() -> (percent: Int, detail: String) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, "Memory unavailable") }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * pageSize
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return (0, "Memory unavailable") }
        let percent = min(max(Int((Double(usedBytes) / Double(totalBytes) * 100).rounded()), 0), 100)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let detail = "\(formatter.string(fromByteCount: Int64(usedBytes))) of \(formatter.string(fromByteCount: Int64(totalBytes)))"
        return (percent, detail)
    }

    nonisolated static func formattedUptime(_ interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval) / 60, 0)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "Up \(days)d \(hours)h" }
        if hours > 0 { return "Up \(hours)h \(minutes)m" }
        return "Up \(minutes)m"
    }
}

private struct CPUTicks {
    let busy: UInt64
    let total: UInt64

    static func current() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var nice: UInt64 = 0
        var idle: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * stride
            user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }
        return CPUTicks(busy: user + system + nice, total: user + system + nice + idle)
    }
}
