import Darwin
import Foundation
import Observation

/// Live CPU, memory, disk and uptime, sampled cheaply from the kernel.
@MainActor
@Observable
final class SystemStats {
    static let shared = SystemStats()

    private(set) var cpuUsage: Double = 0
    private(set) var memoryUsed: Double = 0
    private(set) var memoryTotal: Double = 0
    private(set) var diskUsed: Double = 0
    private(set) var diskTotal: Double = 0
    private(set) var uptime: TimeInterval = 0
    /// Rolling window for the CPU sparkline.
    private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 40)

    private var timer: Timer?
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    private init() {
        memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    }

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var diskFraction: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }

    var memoryLabel: String {
        "\(Int(memoryUsed).byteLabel) / \(Int(memoryTotal).byteLabel)"
    }

    var diskLabel: String {
        "\(Int(diskUsed).byteLabel) / \(Int(diskTotal).byteLabel)"
    }

    var uptimeLabel: String {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    func start(interval: TimeInterval = 2) {
        guard timer == nil else { return }
        sample()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart(interval: TimeInterval) {
        stop()
        start(interval: interval)
    }

    private func sample() {
        cpuUsage = readCPU()
        cpuHistory.removeFirst()
        cpuHistory.append(cpuUsage)
        memoryUsed = readMemoryUsed()
        (diskUsed, diskTotal) = readDisk()
        uptime = ProcessInfo.processInfo.systemUptime
    }

    private func readCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpuUsage }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer { previousTicks = (user, system, idle, nice) }
        guard let previous = previousTicks else { return 0 }

        let userDiff = Double(user &- previous.user)
        let systemDiff = Double(system &- previous.system)
        let idleDiff = Double(idle &- previous.idle)
        let niceDiff = Double(nice &- previous.nice)
        let total = userDiff + systemDiff + idleDiff + niceDiff
        guard total > 0 else { return cpuUsage }
        return min(1, (userDiff + systemDiff + niceDiff) / total)
    }

    private func readMemoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memoryUsed }
        let pageSize = Double(sysconf(_SC_PAGESIZE))
        // "Used" the way Activity Monitor shows it: everything but free + purgeable.
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        return active + wired + compressed
    }

    private func readDisk() -> (Double, Double) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]) else { return (diskUsed, diskTotal) }
        let total = Double(values.volumeTotalCapacity ?? 0)
        let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (max(0, total - available), total)
    }
}
