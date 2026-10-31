import Observation
import SwiftUI

enum RemovalMethod: Sendable {
    /// Recoverable: used for anything the user created or installed.
    case trash
    /// Permanent: used for regenerable junk such as caches and logs.
    case delete
}

/// A support file removed together with its parent item, e.g. an app's caches or launch agent.
struct ExtraFile: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let size: Int64
}

struct CleanItem: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    var name: String
    /// Size of `url` itself, without extras.
    var size: Int64
    var detail: String?
    var extras: [ExtraFile] = []
    /// launchd jobs (login items, bundled agents) to stop before removing the item.
    var launchLabels: [String] = []
    var removal: RemovalMethod
    var selectedByDefault = true
    var duplicateOriginal: URL?
    /// System-wide parts (launch daemons/agents in /Library and their privileged helpers) that
    /// Squeaky can't remove without an administrator. Shown as a warning.
    var systemComponents: [URL] = []
    /// The vendor's own uninstaller, which can remove the system-wide parts.
    var vendorUninstaller: URL?
    /// Owned by another user (usually root, from an installer package), so moving it to the
    /// Trash needs an administrator password; Finder asks for it.
    var needsAdministrator = false

    var totalSize: Int64 { size + extras.reduce(0) { $0 + $1.size } }
}

struct ScanCategory: Identifiable, Sendable {
    enum Metric: Sendable { case size, count }

    let id: String
    var title: String
    var description: String
    var symbol: String
    var metric: Metric = .size
    var items: [CleanItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.totalSize } }

    var headline: String {
        switch metric {
        case .size: "\(totalSize.formattedBytes) of \(title) Found"
        // Titles are plural ("Threats", "Unused Applications"); drop the "s" for a single item.
        case .count: "\(items.count) \(items.count == 1 && title.hasSuffix("s") ? String(title.dropLast()) : title) Found"
        }
    }
}

struct CleanSummary: Equatable, Sendable {
    var freed: Int64 = 0
    var removed = 0
    var failures: [String] = []
    var removedURLs: [URL] = []
    /// The user pressed Cancel before everything was removed.
    var cancelled = false

    mutating func merge(_ other: CleanSummary) {
        freed += other.freed
        removed += other.removed
        failures += other.failures
        removedURLs += other.removedURLs
        cancelled = cancelled || other.cancelled
    }
}

enum ModulePhase: Equatable {
    case idle
    case scanning
    case results
    case reviewing(String?)
    case working
    case done(CleanSummary)
}

struct PendingClean {
    let categoryIDs: Set<String>?
    let count: Int
    let size: Int64
    let hasPermanent: Bool
    let hasTrash: Bool
    let verb: String
    /// Names of selected apps owned by root; Finder will ask for a password to move them.
    var administratorApps: [String] = []
    /// Names of selected apps with system-wide parts that removal leaves running.
    var appsWithSystemParts: [String] = []
    /// When exactly one selected app ships its own uninstaller.
    var vendorUninstaller: (app: String, url: URL)?

    var title: String { "\(verb) \(count == 1 ? "1 item" : "\(count) items")?" }

    var message: String {
        let fate = switch (hasPermanent, hasTrash) {
        case (true, true): "Caches and logs are deleted permanently; everything else is moved to the Trash."
        case (true, false): "These files will be deleted permanently."
        default: "These items will be moved to the Trash."
        }
        var text = "\(size.formattedBytes) selected. \(fate)"
        if !administratorApps.isEmpty {
            text += " \(Self.list(administratorApps)) \(administratorApps.count == 1 ? "was" : "were") installed by an installer, so Finder will ask for your administrator password."
        }
        if !appsWithSystemParts.isEmpty {
            text += " \(Self.list(appsWithSystemParts)) also installed background parts that keep running after removal"
            text += vendorUninstaller != nil ? "; its own uninstaller removes them." : ". The vendor's uninstaller removes them."
        }
        return text
    }

    private static func list(_ names: [String]) -> String {
        names.count <= 2 ? names.joined(separator: " and ") : "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
    }
}

typealias Scanner = @Sendable (ProgressReporter) async -> [ScanCategory]

/// Drives one module (Cleanup, Applications, Declutter) through
/// welcome → scanning → results → review → cleaning → done.
@MainActor @Observable
final class ModuleModel {
    let module: Module
    var phase: ModulePhase = .idle
    var categories: [ScanCategory] = []
    /// Selection is keyed by URL so the same item listed in two categories stays in sync.
    var selection: Set<URL> = []
    /// Support files the user unticked inside an expanded item.
    var excludedExtras: Set<URL> = []
    var pendingClean: PendingClean?
    let reporter = ProgressReporter()
    /// Replaced at the start of each clean, so a past Cancel doesn't affect the next one.
    @ObservationIgnored private var cancelToken = CancelToken()

    @ObservationIgnored private let scanner: Scanner
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<[ScanCategory], Never>?
    @ObservationIgnored private var scanID = UUID()

    init(module: Module, scanner: @escaping Scanner) {
        self.module = module
        self.scanner = scanner
    }

    // MARK: Derived state

    var isReviewing: Bool {
        if case .reviewing = phase { true } else { false }
    }

    var hasResults: Bool { phase == .results || isReviewing }

    func items(in categoryIDs: Set<String>? = nil) -> [CleanItem] {
        var seen = Set<URL>()
        return categories
            .filter { categoryIDs?.contains($0.id) ?? true }
            .flatMap(\.items)
            .filter { seen.insert($0.url).inserted }
    }

    func selectedItems(in categoryIDs: Set<String>? = nil) -> [CleanItem] {
        items(in: categoryIDs).filter { selection.contains($0.url) }
    }

    var totalSize: Int64 { items().reduce(0) { $0 + $1.totalSize } }

    func selectedSize(in categoryIDs: Set<String>? = nil) -> Int64 {
        selectedItems(in: categoryIDs).reduce(0) { $0 + effectiveSize(of: $1) }
    }

    /// The item's size counting only the extras that are still ticked.
    func effectiveSize(of item: CleanItem) -> Int64 {
        item.size + includedExtras(of: item).reduce(0) { $0 + $1.size }
    }

    func includedExtras(of item: CleanItem) -> [ExtraFile] {
        item.extras.filter { !excludedExtras.contains($0.url) }
    }

    func checkState(for category: ScanCategory) -> CheckState {
        let selected = category.items.filter { selection.contains($0.url) }.count
        if selected == 0 { return .off }
        return selected == category.items.count ? .on : .mixed
    }

    var headline: String {
        switch module {
        case .cleanup:
            "There are \(totalSize.formattedBytes) of junk files on your Mac."
        case .applications:
            "We've found \(categories.first { $0.id == "all" }?.items.count ?? 0) apps on your Mac."
        case .protection:
            protectionHeadline
        case .declutter:
            "You have \(items().count) files to sort through.\nUse quick recommendations or review them by hand."
        default:
            ""
        }
    }

    private var protectionHeadline: String {
        let threats = categories.first { $0.id == ProtectionScanner.threatsID }?.items.count ?? 0
        let review = categories.first { $0.id == ProtectionScanner.launchItemsID }?.items.count ?? 0
        if threats > 0 { return "We found \(threats) threat\(threats == 1 ? "" : "s") on your Mac." }
        return "\(ProtectionScanner.lastSummary.status). \(review) launch item\(review == 1 ? "" : "s") could use a look."
    }

        // MARK: Selection

    func toggle(_ item: CleanItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    func toggleExtra(_ extra: ExtraFile) {
        if excludedExtras.contains(extra.url) { excludedExtras.remove(extra.url) } else { excludedExtras.insert(extra.url) }
    }

    func setAll(_ category: ScanCategory, selected: Bool) {
        let urls = category.items.map(\.url)
        if selected { selection.formUnion(urls) } else { selection.subtract(urls) }
    }

    // MARK: Scanning

    func startScan() {
        guard phase != .working else { return }
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    func scan() async {
        guard phase != .working, !Task.isCancelled else { return }
        worker?.cancel()
        let id = UUID()
        scanID = id
        pendingClean = nil
        withAnimation(.easeInOut(duration: 0.4)) { phase = .scanning }
        reporter.report("")
        let scanner = self.scanner
        let reporter = self.reporter
        let worker = Task.detached(priority: .userInitiated) { await scanner(reporter) }
        self.worker = worker

        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard scanID == id else { return }
        guard !Task.isCancelled, !worker.isCancelled else {
            if phase == .scanning { phase = .idle }
            return
        }
        categories = result.filter { !$0.items.isEmpty }
        selection = Set(categories.flatMap { $0.items.filter(\.selectedByDefault).map(\.url) })
        excludedExtras = []
        withAnimation(.easeInOut(duration: 0.4)) { phase = .results }
    }

    func stop() {
        scanID = UUID()
        scanTask?.cancel()
        worker?.cancel()
        withAnimation { phase = .idle }
    }

    func startOver() {
        guard phase != .working else { return }
        stop()
        pendingClean = nil
        categories = []
        selection = []
        excludedExtras = []
        withAnimation { phase = .idle }
    }

    // MARK: Navigation

    func review(_ categoryID: String?) {
        withAnimation(.easeInOut(duration: 0.3)) { phase = .reviewing(categoryID) }
    }

    func backToResults() {
        withAnimation(.easeInOut(duration: 0.3)) { phase = categories.isEmpty ? .idle : .results }
    }

    // MARK: Cleaning

    func requestClean(_ categoryIDs: Set<String>? = nil) {
        let items = selectedItems(in: categoryIDs)
        guard !items.isEmpty else { return }
        pendingClean = PendingClean(
            categoryIDs: categoryIDs,
            count: items.count,
            size: items.reduce(0) { $0 + effectiveSize(of: $1) },
            hasPermanent: items.contains { $0.removal == .delete },
            hasTrash: items.contains { $0.removal == .trash },
            verb: module.actionVerb,
            administratorApps: items.filter(\.needsAdministrator).map(\.name),
            appsWithSystemParts: items.filter { !$0.systemComponents.isEmpty }.map(\.name),
            vendorUninstaller: {
                let withUninstaller = items.filter { $0.vendorUninstaller != nil }
                guard withUninstaller.count == 1, let item = withUninstaller.first, let url = item.vendorUninstaller else { return nil }
                return (item.name, url)
            }()
        )
    }

    func performClean(_ pending: PendingClean) {
        guard hasResults else { return }
        cancelToken = CancelToken()
        withAnimation { phase = .working }
        Task {
            let summary = await removeSelected(in: pending.categoryIDs, cancel: cancelToken)
            // Not animated: an animated switch into the done screen stalled in release builds
            // (the screen stayed on "Cleaning up…"). DoneView fades itself in instead.
            phase = .done(summary)
        }
    }

    /// Stops a running clean after the item currently being removed.
    func cancelClean() {
        cancelToken.cancel()
    }

    /// Removes the selected items without touching `phase`, so Sweep can reuse it.
    /// Progress goes to `reporter`, or to this module's own reporter if none is given.
    func removeSelected(
        in categoryIDs: Set<String>? = nil,
        reporter: ProgressReporter? = nil,
        cancel: CancelToken? = nil
    ) async -> CleanSummary {
        let reporter = reporter ?? self.reporter
        reporter.report("")
        let requests = selectedItems(in: categoryIDs).map {
            RemovalRequest(
                url: $0.url, extras: includedExtras(of: $0).map(\.url), launchLabels: $0.launchLabels,
                size: effectiveSize(of: $0), method: $0.removal, duplicateOriginal: $0.duplicateOriginal
            )
        }
        let summary = await Task.detached(priority: .userInitiated) { () -> CleanSummary in
            #if DEBUG
            // Simulates a long clean, for testing the cleaning screen.
            if let seconds = ProcessInfo.processInfo.environment["SQUEAKY_SLOW_CLEAN"].flatMap(Double.init) {
                usleep(useconds_t(seconds * 1_000_000))
            }
            #endif
            return FileOps.remove(requests, reporter: reporter, cancel: cancel)
        }.value

        let removed = Set(summary.removedURLs)
        for index in categories.indices {
            categories[index].items.removeAll { removed.contains($0.url) }
        }
        categories.removeAll { $0.items.isEmpty }
        selection.subtract(removed)
        if categories.isEmpty, phase == .results { phase = .idle }
        return summary
    }

    /// Drops results whose files have disappeared since the scan, e.g. an app removed by its own
    /// uninstaller or dragged to the Trash. Nothing is rescanned.
    func pruneMissing() {
        guard phase == .results || isReviewing else { return }
        let fileManager = FileManager.default
        // attributesOfItem doesn't follow symlinks, so a dangling link still counts as present.
        let gone = Set(items().map(\.url).filter { (try? fileManager.attributesOfItem(atPath: $0.path)) == nil })
        guard !gone.isEmpty else { return }
        for index in categories.indices {
            categories[index].items.removeAll { gone.contains($0.url) }
        }
        categories.removeAll { $0.items.isEmpty }
        selection.subtract(gone)
        if categories.isEmpty { withAnimation { phase = .idle } }
    }

    func finish() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = categories.isEmpty ? .idle : .results }
    }
}

/// Sweep runs the other modules' scans in parallel and offers a one-click run
/// of the safe recommendations.
@MainActor @Observable
final class SweepModel {
    enum Phase: Equatable { case idle, scanning, results, working, done(CleanSummary) }

    var phase: Phase = .idle
    var includeCleanup = true
    var includeProtection = true
    var includeClutter = true
    var confirmingRun = false

    /// Progress while Run removes things.
    let reporter = ProgressReporter()
    @ObservationIgnored private var runCancel: CancelToken?

    let cleanup: ModuleModel
    let protection: ModuleModel
    let applications: ModuleModel
    let clutter: ModuleModel

    @ObservationIgnored private var task: Task<Void, Never>?

    init(cleanup: ModuleModel, protection: ModuleModel, applications: ModuleModel, clutter: ModuleModel) {
        self.cleanup = cleanup
        self.protection = protection
        self.applications = applications
        self.clutter = clutter
    }

    nonisolated static let duplicatesID = "duplicates"

    var junkSize: Int64 { cleanup.selectedSize() }
    var duplicatesToRemove: Int { clutter.selectedItems(in: [Self.duplicatesID]).count }
    var unusedApps: Int { applications.categories.first { $0.id == "unused" }?.items.count ?? 0 }
    var threatsToRemove: Int { protection.selectedItems(in: [ProtectionScanner.threatsID]).count }

    var canRun: Bool {
        (includeCleanup && junkSize > 0) || (includeProtection && threatsToRemove > 0)
            || (includeClutter && duplicatesToRemove > 0)
    }

    var runMessage: String {
        var parts: [String] = []
        if includeCleanup, junkSize > 0 { parts.append("permanently delete \(junkSize.formattedBytes) of junk") }
        if includeProtection, threatsToRemove > 0 {
            parts.append("move \(threatsToRemove) threat\(threatsToRemove == 1 ? "" : "s") to the Trash")
        }
        if includeClutter, duplicatesToRemove > 0 {
            parts.append("move \(duplicatesToRemove) duplicate download\(duplicatesToRemove == 1 ? "" : "s") to the Trash")
        }
        return "Squeaky will " + parts.joined(separator: " and ") + "."
    }

    var activePath: String {
        [cleanup, protection, applications, clutter].first { $0.phase == .scanning }?.reporter.path ?? ""
    }

    func start() {
        task?.cancel()
        task = Task {
            withAnimation(.easeInOut(duration: 0.4)) { phase = .scanning }
            async let junk: Void = cleanup.scan()
            async let threats: Void = protection.scan()
            async let apps: Void = applications.scan()
            async let files: Void = clutter.scan()
            _ = await (junk, threats, apps, files)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) { phase = .results }
        }
    }

    func stop() {
        task?.cancel()
        withAnimation { phase = .idle }
    }

    func run() {
        let cancel = CancelToken()
        runCancel = cancel
        task = Task {
            withAnimation { phase = .working }
            var summary = CleanSummary()
            if includeCleanup { summary.merge(await cleanup.removeSelected(reporter: reporter, cancel: cancel)) }
            if includeProtection, !cancel.isCancelled {
                summary.merge(await protection.removeSelected(in: [ProtectionScanner.threatsID], reporter: reporter, cancel: cancel))
            }
            if includeClutter, !cancel.isCancelled {
                summary.merge(await clutter.removeSelected(in: [Self.duplicatesID], reporter: reporter, cancel: cancel))
            }
            if cancel.isCancelled { summary.cancelled = true }
            // Not animated, see ModuleModel.performClean.
            phase = .done(summary)
        }
    }

    /// Stops Run after the item currently being removed; later sections are skipped.
    func cancelRun() {
        runCancel?.cancel()
    }

    func finish() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .idle }
    }
}

@MainActor @Observable
final class AppState {
    var selection: Module = .sweep
    var hasFullDiskAccess = Permissions.hasFullDiskAccess
    var showingPermissions = false
    /// Set once the user has been sent to System Settings, so the card can offer a relaunch.
    var openedPermissionSettings = false
    /// Bumped to fire a new confetti burst over the window.
    var confettiBursts = 0

    private static let skippedPermissionsKey = "skippedFullDiskAccessPrompt"

    let cleanup = ModuleModel(module: .cleanup, scanner: { await JunkScanner.scan($0) })
    let applications = ModuleModel(module: .applications, scanner: { await AppScanner.scan($0) })
    let protection = ModuleModel(module: .protection, scanner: { await ProtectionScanner.scan($0) })
    let performance = PerformanceModel()
    let clutter = ModuleModel(module: .declutter, scanner: { await ClutterScanner.scan($0) })
    let sweep: SweepModel

    @ObservationIgnored private var folderWatchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingRefresh: DispatchWorkItem?

    init() {
        sweep = SweepModel(cleanup: cleanup, protection: protection, applications: applications, clutter: clutter)
        watchApplicationFolders()
    }

    /// Catches up with changes made outside Squeaky (vendor uninstallers, Finder, other apps):
    /// drops results that no longer exist and re-reads startup items.
    func refreshAfterExternalChanges() {
        [cleanup, protection, applications, clutter].forEach { $0.pruneMissing() }
        if performance.hasInspected { Task { await performance.inspect() } }
    }

    /// Apps can disappear while Squeaky is in the background, e.g. when a vendor's uninstaller
    /// runs, so watch the Applications folders and refresh shortly after they change.
    private func watchApplicationFolders() {
        for path in ["/Applications", FileUtils.home.appendingPathComponent("Applications").path] {
            let descriptor = Darwin.open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleRefresh() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            folderWatchers.append(source)
        }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshAfterExternalChanges() }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func model(for module: Module) -> ModuleModel? {
        switch module {
        case .cleanup: cleanup
        case .protection: protection
        case .applications: applications
        case .declutter: clutter
        default: nil
        }
    }

    enum Badge { case none, busy, results }

    func badge(for module: Module) -> Badge {
        if module == .sweep {
            switch sweep.phase {
            case .scanning, .working: return .busy
            case .results: return .results
            default: return .none
            }
        }
        guard let model = model(for: module) else { return .none }
        switch model.phase {
        case .scanning, .working: return .busy
        case .results, .reviewing: return .results
        default: return .none
        }
    }

    func celebrate() {
        confettiBursts += 1
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    /// Shown on launch until access is granted or the user picks "Not Now".
    func promptForPermissionsIfNeeded() {
        guard !hasFullDiskAccess, !UserDefaults.standard.bool(forKey: Self.skippedPermissionsKey) else { return }
        showingPermissions = true
    }

    func dismissPermissions() {
        if !hasFullDiskAccess { UserDefaults.standard.set(true, forKey: Self.skippedPermissionsKey) }
        withAnimation(.easeInOut(duration: 0.25)) { showingPermissions = false }
    }

    func open(_ module: Module, reviewing categoryID: String? = nil) {
        // Enter the review before switching screens so the new screen is built in that phase.
        // Changing both in one animated update left the results page on screen while the
        // phase said reviewing, and re-tapping Review then set an equal phase and did nothing.
        model(for: module)?.phase = .reviewing(categoryID)
        withAnimation(.easeInOut(duration: 0.35)) { selection = module }
    }

    /// Takes the user to the app list in Applications, scanning first if that hasn't happened yet.
    func showUninstaller() {
        if applications.hasResults {
            open(.applications, reviewing: "all")
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { selection = .applications }
            if applications.phase != .scanning { applications.startScan() }
        }
    }
}
