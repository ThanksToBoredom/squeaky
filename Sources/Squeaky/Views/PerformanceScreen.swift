import SwiftUI

/// A live dashboard rather than a scan: resource use, the apps using it, what starts in the
/// background, and local snapshots. Nothing here "optimises" anything behind your back.
struct PerformanceScreen: View {
    @Bindable var model: PerformanceModel
    @Environment(AppState.self) private var app

    @ViewState private var showAllProcesses = false
    @ViewState private var snapshotToDelete: LocalSnapshot?
    @ViewState private var startupToRemove: StartupItem?

    private let palette = Module.performance.palette

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: Module.performance.title)
            ScrollView {
                VStack(spacing: 14) {
                    header
                    HStack(spacing: 14) {
                        MeterCard(
                            title: "CPU",
                            fraction: model.cpu ?? 0,
                            value: model.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "…",
                            detail: "\(SystemSampler.processorCount) cores"
                        )
                        MeterCard(
                            title: "Memory",
                            fraction: Double(model.memoryUsed) / Double(max(model.memoryTotal, 1)),
                            value: model.memoryUsed > 0 ? model.memoryUsed.formattedBytes : "…",
                            detail: "used of \(model.memoryTotal.formattedBytes)"
                        )
                        MeterCard(
                            title: "Disk",
                            fraction: diskFraction,
                            value: model.diskFree.map { "\($0.formattedBytes) free" } ?? "…",
                            detail: model.diskTotal.map { "of \($0.formattedBytes)" } ?? ""
                        )
                    }
                    processesCard
                    startupCard
                    snapshotsCard
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            model.startMonitoring()
            if !model.hasInspected { Task { await model.inspect() } }
        }
        .onDisappear { model.stopMonitoring() }
        .alert(
            "Delete this snapshot?",
            isPresented: Binding(get: { snapshotToDelete != nil }, set: { if !$0 { snapshotToDelete = nil } }),
            presenting: snapshotToDelete
        ) { snapshot in
            Button("Delete", role: .destructive) { Task { await model.delete(snapshot) } }
            Button("Cancel", role: .cancel) {}
        } message: { snapshot in
            Text("The Time Machine snapshot from \(snapshot.date.map(Self.dateText) ?? snapshot.identifier) will be deleted permanently. Your Time Machine backups on other disks aren't affected.")
        }
        .alert(
            "Remove this startup item?",
            isPresented: Binding(get: { startupToRemove != nil }, set: { if !$0 { startupToRemove = nil } }),
            presenting: startupToRemove
        ) { item in
            Button("Remove", role: .destructive) { Task { await model.remove(item) } }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("“\(item.label)” will be stopped and its file moved to the Trash. The app it belongs to may add it back the next time it runs; if so, remove the app itself in Applications.")
        }
        .alert(
            "The startup item couldn't be removed",
            isPresented: Binding(get: { model.startupError != nil }, set: { if !$0 { model.startupError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.startupError ?? "")
        }
        .alert(
            "The snapshot couldn't be deleted",
            isPresented: Binding(get: { model.snapshotError != nil }, set: { if !$0 { model.snapshotError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.snapshotError ?? "")
        }
    }

    private var diskFraction: Double {
        guard let free = model.diskFree, let total = model.diskTotal, total > 0 else { return 0 }
        return 1 - Double(free) / Double(total)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Mac right now")
                    .font(.system(size: 22, weight: .semibold))
                Text("Live resource use, what starts in the background, and local snapshots.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
            Button("Refresh") { Task { await model.inspect() } }
                .buttonStyle(GlassButtonStyle())
                .disabled(model.isInspecting)
            Button("Activity Monitor") { PerformanceModel.openActivityMonitor() }
                .buttonStyle(GlassButtonStyle())
        }
    }

    // MARK: Apps and processes

    private var processesCard: some View {
        let all = model.sortedProcesses
        let shown = showAllProcesses ? all : Array(all.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryBadge(symbol: "cpu", palette: palette, size: 34)
                Text("Apps and processes")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("Sort by", selection: $model.sort) {
                    ForEach(PerformanceModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            if all.isEmpty {
                Text("Measuring apps and processes…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                HStack {
                    Text("Name")
                    Spacer()
                    Text("CPU").frame(width: 70, alignment: .trailing)
                    Text("Memory").frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)
                VStack(spacing: 2) {
                    ForEach(shown) { ProcessRow(usage: $0) }
                }
                HStack {
                    if all.count > 8 {
                        TextLink(title: showAllProcesses ? "Show top 8" : "Show all \(all.count)") {
                            withAnimation(.easeInOut(duration: 0.2)) { showAllProcesses.toggle() }
                        }
                    }
                    Spacer()
                    Text("Your apps only; system processes aren't listed. Helpers are grouped with their app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    // MARK: Startup items

    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryBadge(symbol: "power", palette: palette, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hasInspected ? "\(model.startupItems.count) startup and background items" : "Startup and background items")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Remove your own agents here. Turn off system-wide ones in Login Items & Extensions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Button("Login Items Settings") { PerformanceModel.openLoginItemsSettings() }
                    .buttonStyle(GlassButtonStyle())
            }
            if !model.hasInspected {
                ProgressView().controlSize(.small).tint(.white).padding(.vertical, 8)
            } else if model.startupItems.isEmpty {
                Text("Nothing starts in the background.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 2) {
                    ForEach(model.startupItems) { item in
                        StartupRow(
                            item: item,
                            removing: model.removingStartupID == item.id,
                            onRemove: item.domain == .user ? { startupToRemove = item } : nil,
                            onUninstallApp: item.domain != .user && (item.appPath?.hasPrefix("/Applications/") ?? false)
                                ? { app.showUninstaller() } : nil
                        )
                    }
                }
            }
            ForEach(model.issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.yellow.opacity(0.9))
            }
        }
        .padding(18)
        .glassCard()
    }

    // MARK: Snapshots

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryBadge(symbol: "clock.arrow.circlepath", palette: palette, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local snapshots")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Snapshots Time Machine and macOS updates keep on your startup disk.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Button("Time Machine Settings") { PerformanceModel.openTimeMachineSettings() }
                    .buttonStyle(GlassButtonStyle())
            }
            if !model.hasInspected {
                ProgressView().controlSize(.small).tint(.white).padding(.vertical, 8)
            } else if model.snapshots.isEmpty {
                Text("There are no local snapshots on your startup disk.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 2) {
                    ForEach(model.snapshots) { snapshot in
                        SnapshotRow(
                            snapshot: snapshot,
                            deleting: model.deletingSnapshotID == snapshot.id,
                            onDelete: { snapshotToDelete = snapshot }
                        )
                    }
                }
                Text("macOS doesn't report how much space each snapshot uses. Only Time Machine snapshots can be deleted here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Pieces

private struct MeterCard: View {
    let title: String
    let fraction: Double
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: fraction)
                Text("\(Int((min(1, fraction) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

private struct ProcessRow: View {
    let usage: ProcessUsage

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: URL(fileURLWithPath: usage.iconPath)))
                .resizable()
                .frame(width: 22, height: 22)
            Text(usage.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if usage.processCount > 1 {
                Text("\(usage.processCount) processes")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(usage.cpu.map { String(format: "%.1f%%", $0 * 100) } ?? "–")
                .frame(width: 70, alignment: .trailing)
            Text(usage.memory.formattedBytes)
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct StartupRow: View {
    let item: StartupItem
    var removing = false
    /// Only the user's own launch agents can be removed (system-wide ones need an administrator).
    var onRemove: (() -> Void)?
    /// For system-wide items belonging to an installed app: go and uninstall the app instead.
    var onUninstallApp: (() -> Void)?

    @ViewState private var hovering = DebugSnapshot.forcesHover

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let app = item.appPath {
                    Image(nsImage: IconCache.icon(for: URL(fileURLWithPath: app))).resizable()
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let program = item.program {
                    Text((program as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 5) {
                    Chip(text: item.domain.rawValue)
                    ForEach(item.triggers, id: \.self) { Chip(text: $0) }
                    if item.isDisabled { Chip(text: "Disabled", warning: true) }
                    if !item.programExists { Chip(text: "Program missing", warning: true) }
                }
            }
            Spacer(minLength: 8)
            // Centred against each other and vertically within the row. Shown only while hovering
            // (they keep their space, so rows don't shift), except the progress spinner.
            HStack(spacing: 10) {
                if removing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Group {
                        if let onRemove {
                            Button("Remove", action: onRemove)
                                .buttonStyle(GlassButtonStyle())
                        } else {
                            if let onUninstallApp {
                                Button("Uninstall App", action: onUninstallApp)
                                    .buttonStyle(GlassButtonStyle())
                                    .help("Removing the app removes its background items too")
                            }
                            // System-wide items need an administrator; macOS can switch them off, reversibly.
                            Button("Turn Off…") { PerformanceModel.openLoginItemsSettings() }
                                .buttonStyle(GlassButtonStyle())
                                .help("Opens Login Items & Extensions, where you can switch this off under Allow in the Background")
                        }
                    }
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.plist])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
    }
}

private struct SnapshotRow: View {
    let snapshot: LocalSnapshot
    let deleting: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.kind == .timeMachine ? "clock.arrow.circlepath" : "externaldrive.fill")
                .font(.system(size: 14))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.date.map(PerformanceScreen.dateText) ?? snapshot.identifier)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(snapshot.kind.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if deleting {
                ProgressView().controlSize(.small).tint(.white)
            } else if snapshot.deletionTimestamp != nil {
                Button("Delete", action: onDelete).buttonStyle(GlassButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct Chip: View {
    let text: String
    var warning = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(warning ? Color.yellow.opacity(0.95) : .white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(.white.opacity(warning ? 0.1 : 0.14)))
    }
}
