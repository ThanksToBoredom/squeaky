import AppKit
import Observation

/// Live resource use (sampled while the Performance page is open), startup items and local snapshots.
@MainActor @Observable
final class PerformanceModel {
    enum Sort: String, CaseIterable, Identifiable {
        case cpu = "CPU", memory = "Memory"
        var id: Self { self }
    }

    private(set) var cpu: Double?
    private(set) var memoryUsed: Int64 = 0
    let memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    private(set) var diskFree: Int64?
    private(set) var diskTotal: Int64?
    private(set) var processes: [ProcessUsage] = []
    var sort: Sort = .cpu

    private(set) var startupItems: [StartupItem] = []
    private(set) var snapshots: [LocalSnapshot] = []
    private(set) var issues: [String] = []
    private(set) var isInspecting = false
    private(set) var hasInspected = false
    private(set) var deletingSnapshotID: String?
    var snapshotError: String?
    private(set) var removingStartupID: String?
    var startupError: String?

    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var previous: SystemSample?
    @ObservationIgnored private var previousTime: UInt64 = 0

    var sortedProcesses: [ProcessUsage] {
        switch sort {
        case .cpu: processes.sorted { ($0.cpu ?? 0, $0.memory) > ($1.cpu ?? 0, $1.memory) }
        case .memory: processes.sorted { $0.memory > $1.memory }
        }
    }

    // MARK: Live monitoring

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        previous = nil
    }

    private func tick() async {
        let sample = await Task.detached(priority: .utility) { SystemSampler.sample() }.value
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previous == nil ? 0 : now - previousTime

        if let previous, sample.totalTicks > previous.totalTicks {
            cpu = Double(sample.busyTicks - previous.busyTicks) / Double(sample.totalTicks - previous.totalTicks)
        }
        memoryUsed = sample.memoryUsed
        diskFree = sample.diskFree
        diskTotal = sample.diskTotal
        processes = SystemSampler.usage(current: sample, previous: previous, elapsedNanos: elapsed)
        previous = sample
        previousTime = now
    }

    // MARK: Startup items and snapshots

    func inspect() async {
        guard !isInspecting else { return }
        isInspecting = true
        let (startup, snapshotResult) = await Task.detached(priority: .userInitiated) {
            (StartupInspector.startupItems(), StartupInspector.snapshots())
        }.value
        startupItems = startup.items
        snapshots = snapshotResult.snapshots
        issues = startup.issues + snapshotResult.issues
        isInspecting = false
        hasInspected = true
    }

    func delete(_ snapshot: LocalSnapshot) async {
        deletingSnapshotID = snapshot.id
        let error = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try StartupInspector.delete(snapshot)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        deletingSnapshotID = nil
        if let error { snapshotError = error }
        await inspect()
    }

    /// Stops one of the user's own launch agents and moves its file to the Trash.
    func remove(_ item: StartupItem) async {
        guard item.domain == .user else { return }
        removingStartupID = item.id
        let request = RemovalRequest(url: item.plist, extras: [], size: 0, method: .trash)
        let summary = await Task.detached(priority: .userInitiated) { FileOps.remove([request]) }.value
        removingStartupID = nil
        if let failure = summary.failures.first { startupError = failure }
        await inspect()
    }

    // MARK: Shortcuts

    static func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    static func openLoginItemsSettings() {
        openSettings(["com.apple.LoginItems-Settings.extension", "com.apple.preferences.users"])
    }

    static func openTimeMachineSettings() {
        openSettings(["com.apple.Time-Machine-Settings.extension", "com.apple.prefs.backup"])
    }

    private static func openSettings(_ panes: [String]) {
        for pane in panes {
            if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) { return }
        }
    }
}
