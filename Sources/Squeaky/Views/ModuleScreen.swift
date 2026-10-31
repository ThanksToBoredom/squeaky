import SwiftUI

/// Cleanup, Applications and Declutter all share this flow.
struct ModuleScreen: View {
    @Bindable var model: ModuleModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.module.title, backTitle: backTitle, onBack: back)
            ZStack {
                switch model.phase {
                case .idle:
                    WelcomeView(module: model.module, buttonTitle: "Scan") { model.startScan() }
                case .scanning:
                    ScanningView(
                        module: model.module,
                        title: model.module.scanningTitle,
                        path: { [reporter = model.reporter] in reporter.path },
                        buttonTitle: "Stop",
                        onStop: model.stop
                    )
                case .results:
                    ResultsView(model: model)
                case .reviewing(let categoryID):
                    ReviewView(model: model, initialCategoryID: categoryID)
                case .working:
                    ScanningView(
                        module: model.module,
                        title: "Cleaning up…",
                        path: { [reporter = model.reporter] in reporter.path },
                        buttonTitle: "Cancel",
                        onStop: model.cancelClean
                    )
                case .done(let summary):
                    DoneView(module: model.module, summary: summary, onDone: model.finish)
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            Text(model.pendingClean?.title ?? ""),
            isPresented: Binding(
                get: { model.pendingClean != nil },
                set: { if !$0 { model.pendingClean = nil } }
            ),
            presenting: model.pendingClean
        ) { pending in
            if let uninstaller = pending.vendorUninstaller {
                // Usually the better choice: it also removes the app's system-wide parts.
                Button("Open \(uninstaller.app) Uninstaller") { NSWorkspace.shared.open(uninstaller.url) }
            }
            Button(pending.verb, role: .destructive) { model.performClean(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private var backTitle: String? {
        switch model.phase {
        case .reviewing: "Back"
        default: nil
        }
    }

    private func back() {
        model.backToResults()
    }
}

// MARK: - Results

struct ResultsView: View {
    let model: ModuleModel

    var body: some View {
        // Headline and grid form one block, centred vertically by the equal spacers around it.
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(spacing: 18) {
                Text(model.categories.isEmpty && model.module != .protection ? "Your Mac looks spotless." : model.headline)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                if !model.categories.isEmpty {
                    Button(model.module.reviewAllTitle) { model.review(nil) }
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(.bottom, 40)

            if model.categories.isEmpty {
                EmptyResults(module: model.module)
            } else if let first = model.categories.first {
                let rest = Array(model.categories.dropFirst().prefix(4))
                GeometryReader { proxy in
                    HStack(spacing: 14) {
                        CategoryCard(category: first, model: model, large: true)
                            .frame(width: rest.isEmpty ? proxy.size.width : (proxy.size.width - 28) / 3)
                        if !rest.isEmpty {
                            VStack(spacing: 14) {
                                ForEach(Array(stride(from: 0, to: rest.count, by: 2)), id: \.self) { index in
                                    HStack(spacing: 14) {
                                        CategoryCard(category: rest[index], model: model)
                                        if index + 1 < rest.count {
                                            CategoryCard(category: rest[index + 1], model: model)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(minHeight: 320, maxHeight: 380)
            }

            Spacer(minLength: 16)
            // No primary button here, so "Start Over" takes its place.
            ResultsFooter(onStartOver: model.startOver)
        }
        .padding(.horizontal, 32)
    }
}

private struct EmptyResults: View {
    let module: Module

    var body: some View {
        HStack(spacing: 18) {
            CategoryBadge(symbol: "checkmark", palette: module.palette, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(module == .protection ? ProtectionScanner.lastSummary.status : "Nothing to clean up here")
                    .font(.system(size: 19, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: 620)
        .glassCard(cornerRadius: 22)
    }

    private var message: String {
        guard module == .protection else {
            return "If you denied Squeaky access to some folders, allow it in System Settings → Privacy & Security → Files & Folders (or Full Disk Access) and scan again."
        }
        let summary = ProtectionScanner.lastSummary
        guard let version = summary.catalogVersion else {
            return "Squeaky couldn't read Apple's XProtect malware definitions on this Mac, so nothing was checked."
        }
        if !summary.issues.isEmpty { return summary.issues.joined(separator: " ") }
        let date = summary.catalogUpdated.map { " (updated \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
        return "Checked \(summary.filesScanned) apps, launch items and downloaded files against Apple's XProtect malware definitions, version \(version)\(date). Apple keeps these up to date automatically."
    }
}

private struct CategoryCard: View {
    let category: ScanCategory
    let model: ModuleModel
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.headline)
                        .font(.system(size: large ? 19 : 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if large {
                        Text(category.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if !large {
                    CategoryBadge(symbol: category.symbol, palette: model.module.palette, size: 36)
                }
            }
            if let art {
                art
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 8)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Review") { model.review(category.id) }
                    .buttonStyle(GlassButtonStyle())
                if !model.selectedItems(in: [category.id]).isEmpty {
                    Button(model.module.actionVerb) { model.requestClean([category.id]) }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private var art: AnyView? {
        switch category.id {
        case "unused":
            AnyView(IconWall(icons: wallURLs.map(IconCache.icon(for:)), columns: 8, rows: 10))
        case "large":
            AnyView(IconWall(icons: IconWall.fileIcons(for: category.items.map(\.url))))
        case "leftovers":
            AnyView(FastFoodArt())
        default:
            // Apps get the carousel; folders and files a grid of equal-size icons across the card.
            !large ? nil
                : model.module == .applications ? AnyView(IconStrip(urls: category.items.prefix(5).map(\.url)))
                : AnyView(IconWall(
                    icons: IconWall.fileIcons(for: category.items.map(\.url), fillers: [.folder]),
                    cellSize: 64,
                    spacing: 14,
                    fill: category.metric == .size ? Self.fill(for: category.totalSize) : nil
                ))
        }
    }

    /// How much of the grid to fill for this many bytes, on a log scale: 1 MB or less shows a
    /// single icon, 10 GB or more fills the card.
    static func fill(for bytes: Int64) -> Double {
        let megabytes = Double(bytes) / 1_048_576
        guard megabytes > 1 else { return 0 }
        return min(1, log10(megabytes) / 4)
    }

        /// The unused apps first, then the rest of the installed apps to fill the wall.
    private var wallURLs: [URL] {
        let unused = category.items.map(\.url)
        let unusedSet = Set(unused)
        let others = model.categories.first { $0.id == "all" }?.items.map(\.url).filter { !unusedSet.contains($0) } ?? []
        return Array((unused + others).prefix(80))
    }
}
