import Foundation

/// "The Mac is working hard": CPU load over the last poll interval, or the system
/// reporting thermal pressure (which is when it starts throttling the CPU).
final class StressMonitor {
    private(set) var stressed = false
    var onChange: (() -> Void)?

    /// Start pulsing at this load; stop only once it falls below `calmLoad`,
    /// so a load hovering at the threshold doesn't flicker.
    private static let busyLoad = 0.80
    private static let calmLoad = 0.70

    private var lastTicks: (busy: UInt64, total: UInt64)?
    private(set) var load = 0.0

    init() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() }
        refresh()
    }

    /// Call on the regular poll; the load is the average since the previous call.
    func refresh() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                load = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
        evaluate()
    }

    private func evaluate() {
        let thermal = ProcessInfo.processInfo.thermalState
        let hot = thermal == .serious || thermal == .critical
        let busy = stressed ? load >= Self.calmLoad : load >= Self.busyLoad
        let now = hot || busy
        guard now != stressed else { return }
        stressed = now
        onChange?()
    }

    /// Cumulative CPU ticks across all cores.
    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        return (user + system + nice, user + system + idle + nice)
    }
}
