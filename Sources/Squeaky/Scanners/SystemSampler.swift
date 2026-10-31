import Darwin
import Foundation

/// One process's counters at a moment in time.
struct ProcessReading: Sendable {
    let path: String
    /// User + system CPU time used so far, in nanoseconds.
    let cpuNanos: UInt64
    let resident: Int64
}

/// A point-in-time reading of the whole Mac. CPU figures only mean something as the
/// difference between two samples.
struct SystemSample: Sendable {
    var busyTicks: UInt64 = 0
    var totalTicks: UInt64 = 0
    var memoryUsed: Int64 = 0
    var diskFree: Int64?
    var diskTotal: Int64?
    var processes: [pid_t: ProcessReading] = [:]
}

/// An app (with its helpers grouped in) or a standalone process, ready to display.
struct ProcessUsage: Identifiable, Sendable {
    /// The app bundle's path, or the executable's path for standalone processes.
    let id: String
    let name: String
    let iconPath: String
    let processCount: Int
    /// Share of the whole Mac's CPU capacity, 0...1. Nil until two samples exist.
    let cpu: Double?
    let memory: Int64
}

enum SystemSampler {
    static func cpuFraction(current: SystemSample, previous: SystemSample?) -> Double? {
        guard let previous, current.totalTicks > previous.totalTicks,
              current.busyTicks >= previous.busyTicks else { return nil }
        return min(1, Double(current.busyTicks - previous.busyTicks) / Double(current.totalTicks - previous.totalTicks))
    }

    static let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)

    /// Mach time units to nanoseconds (1 on Intel, 125/3 on Apple silicon).
    private static let nanosPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    static func sample() -> SystemSample {
        var sample = SystemSample()
        sampleCPU(into: &sample)
        sampleMemory(into: &sample)
        sampleDisk(into: &sample)
        sample.processes = sampleProcesses()
        return sample
    }

    private static func sampleCPU(into sample: inout SystemSample) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        sample.busyTicks = user + system + nice
        sample.totalTicks = user + system + nice + idle
    }

    /// Memory in use: active, wired and compressed pages (what Activity Monitor calls "Memory Used" is close).
    private static func sampleMemory(into sample: inout SystemSample) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pages = Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        sample.memoryUsed = pages * Int64(vm_kernel_page_size)
    }

    private static func sampleDisk(into sample: inout SystemSample) {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        sample.diskFree = values.volumeAvailableCapacityForImportantUsage
        sample.diskTotal = values.volumeTotalCapacity.map(Int64.init)
    }

    /// The current user's processes. Other users' and system processes aren't readable without root.
    private static func sampleProcesses() -> [pid_t: ProcessReading] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        let uid = getuid()
        var readings: [pid_t: ProcessReading] = [:]
        var pathBuffer = [CChar](repeating: 0, count: 4096)

        for pid in pids.prefix(Int(max(0, count))) where pid > 0 {
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size,
                  info.pbsd.pbi_uid == uid
            else { continue }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            let ticks = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            readings[pid] = ProcessReading(
                path: String(cString: pathBuffer),
                cpuNanos: UInt64(Double(ticks) * nanosPerTick),
                resident: Int64(info.ptinfo.pti_resident_size)
            )
        }
        return readings
    }

    /// Groups processes by app (helpers inside an app's bundle count towards the app) and
    /// works out each group's CPU share between two samples.
    static func usage(current: SystemSample, previous: SystemSample?, elapsedNanos: UInt64) -> [ProcessUsage] {
        struct Group { var pids = 0; var cpuNanos: UInt64 = 0; var hasCPU = false; var memory: Int64 = 0 }
        var groups: [String: Group] = [:]
        for (pid, reading) in current.processes {
            let key = appBundlePath(for: reading.path) ?? reading.path
            var group = groups[key] ?? Group()
            group.pids += 1
            group.memory += reading.resident
            if let before = previous?.processes[pid], before.path == reading.path, reading.cpuNanos >= before.cpuNanos {
                group.cpuNanos += reading.cpuNanos - before.cpuNanos
                group.hasCPU = true
            }
            groups[key] = group
        }
        let capacity = Double(max(elapsedNanos, 1)) * Double(processorCount)
        return groups.map { key, group in
            let isApp = key.hasSuffix(".app")
            let name = isApp
                ? FileManager.default.displayName(atPath: key).replacingOccurrences(of: ".app", with: "")
                : (key as NSString).lastPathComponent
            return ProcessUsage(
                id: key,
                name: name,
                iconPath: key,
                processCount: group.pids,
                cpu: group.hasCPU ? min(1, Double(group.cpuNanos) / capacity) : nil,
                memory: group.memory
            )
        }
    }

    /// `/Applications/Foo.app/Contents/Frameworks/Helper.app/…` → `/Applications/Foo.app`.
    static func appBundlePath(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
