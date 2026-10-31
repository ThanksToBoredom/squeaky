import SwiftUI

struct SweepScreen: View {
    @Bindable var model: SweepModel
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: Module.sweep.title)
            ZStack {
                switch model.phase {
                case .idle:
                    WelcomeView(module: .sweep, buttonTitle: "Scan") {
                        model.start()
                        Task { await app.performance.inspect() }
                    }
                case .scanning:
                    ScanningView(
                        module: .sweep,
                        title: Module.sweep.scanningTitle,
                        path: { model.activePath },
                        steps: [
                            ("Cleanup", model.cleanup.phase != .scanning),
                            ("Protection", model.protection.phase != .scanning),
                            ("Applications", model.applications.phase != .scanning),
                            ("Declutter", model.clutter.phase != .scanning),
                        ],
                        buttonTitle: "Stop",
                        onStop: model.stop
                    )
                case .results:
                    results
                case .working:
                    ScanningView(
                        module: .sweep,
                        title: "Running tasks…",
                        path: { [reporter = model.reporter] in reporter.path },
                        buttonTitle: "Cancel",
                        onStop: model.cancelRun
                    )
                case .done(let summary):
                    DoneView(module: .sweep, summary: summary, onDone: model.finish)
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Run Sweep?", isPresented: $model.confirmingRun) {
            Button("Run", role: .destructive, action: model.run)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.runMessage)
        }
    }

    private var results: some View {
        // Headline and grid form one block, centred between the title bar and the Run button.
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            Text("Your tasks are ready to run. Look what we found:")
                .font(.system(size: 22, weight: .semibold))
                .padding(.bottom, 32)

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    SweepCard(
                        module: .cleanup,
                        value: model.junkSize > 0 ? "\(model.junkSize.formattedBytes) of junk" : "No junk",
                        caption: "to clean",
                        isOn: model.junkSize > 0 ? $model.includeCleanup : nil,
                        onReview: model.cleanup.hasResults ? { app.open(.cleanup) } : nil
                    )
                    SweepCard(
                        module: .protection,
                        value: model.threatsToRemove > 0
                            ? "\(model.threatsToRemove) threat\(model.threatsToRemove == 1 ? "" : "s")"
                            : ProtectionScanner.lastSummary.status,
                        caption: model.threatsToRemove > 0 ? "to remove" : "within the scan scope",
                        isOn: model.threatsToRemove > 0 ? $model.includeProtection : nil,
                        onReview: model.protection.hasResults ? { app.open(.protection) } : nil
                    )
                    SweepCard(
                        module: .performance,
                        value: app.performance.hasInspected ? "\(app.performance.startupItems.count) startup items" : "Checking…",
                        caption: "start in the background",
                        onReview: app.performance.hasInspected ? { app.open(.performance) } : nil
                    )
                }
                HStack(spacing: 14) {
                    SweepCard(
                        module: .applications,
                        value: model.unusedApps > 0 ? "\(model.unusedApps) unused apps" : "No unused apps",
                        caption: "to review",
                        onReview: model.applications.hasResults ? { app.open(.applications, reviewing: "unused") } : nil
                    )
                    SweepCard(
                        module: .declutter,
                        value: model.duplicatesToRemove > 0 ? "\(model.duplicatesToRemove) duplicate downloads" : "No duplicate downloads",
                        caption: "to remove",
                        isOn: model.duplicatesToRemove > 0 ? $model.includeClutter : nil,
                        onReview: model.clutter.hasResults ? { app.open(.declutter, reviewing: SweepModel.duplicatesID) } : nil
                    )
                }
            }

            Spacer(minLength: 20)
            ResultsFooter(onStartOver: model.finish) {
                PrimaryActionButton(title: "Run", palette: Module.sweep.palette, enabled: model.canRun) {
                    model.confirmingRun = true
                }
            }
        }
        .padding(.horizontal, 32)
    }
}

private struct SweepCard: View {
    let module: Module
    let value: String
    let caption: String
    var isOn: Binding<Bool>?
    var onReview: (() -> Void)?
    var dimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack(alignment: .topTrailing) {
            HeroIcon(module: module, size: 120, floating: false)
                .rotationEffect(.degrees(-10))
                .offset(x: 26, y: -30)
                .opacity(dimmed ? 0.45 : 0.95)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let isOn {
                        CheckBox(state: isOn.wrappedValue ? .on : .off) { isOn.wrappedValue.toggle() }
                    }
                    Text(module.title).font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if let onReview {
                        Button("Review", action: onReview).buttonStyle(GlassButtonStyle())
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(
            colors: [module.palette.glow.opacity(0.35), Color.white.opacity(0.06)],
            startPoint: .topTrailing, endPoint: .bottomLeading
        ))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.15)))
        .opacity(dimmed ? 0.75 : 1)
    }
}
