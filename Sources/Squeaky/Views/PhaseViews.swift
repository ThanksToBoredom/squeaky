import SwiftUI

struct WelcomeView: View {
    let module: Module
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            HeroStage(module: module, size: 220)
            Spacer().frame(height: 52)
            Text(module.welcomeTitle)
                .font(.system(size: 42, weight: .regular))
            Text(module.welcomeSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.top, 10)
            Spacer(minLength: 20)
            Group {
                if let buttonTitle, let action {
                    PrimaryActionButton(title: buttonTitle, palette: module.palette, action: action)
                } else {
                    Text("Coming soon")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassCard(cornerRadius: 10)
                }
            }
            .frame(height: 56)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScanningView: View {
    let module: Module
    let title: String
    var path: (() -> String)?
    var steps: [(title: String, done: Bool)] = []
    var buttonTitle: String
    var onStop: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            HeroStage(module: module, size: 220, busy: true)
            Spacer().frame(height: 52)
            Text(title)
                .font(.system(size: 42, weight: .regular))
            Group {
                if let path {
                    TimelineView(.periodic(from: .now, by: 0.12)) { _ in
                        Text((path() as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: 600)
            .padding(.top, 10)

            if !steps.isEmpty {
                HStack(spacing: 18) {
                    ForEach(steps, id: \.title) { step in
                        HStack(spacing: 6) {
                            if step.done {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text(step.title)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(step.done ? 1 : 0.7))
                    }
                }
                .padding(.top, 18)
                .animation(.easeInOut, value: steps.map(\.done))
            }

            Spacer(minLength: 20)
            PrimaryActionButton(title: buttonTitle, palette: module.palette, busy: true, enabled: onStop != nil) {
                onStop?()
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DoneView: View {
    let module: Module
    let summary: CleanSummary
    let onDone: () -> Void

    @Environment(AppState.self) private var app

    @ViewState private var showingLog = false
    /// Fades the screen in on appear (the switch to it isn't animated, see performClean).
    @ViewState private var shown = false

    private static let bubbleArea = CGSize(width: 960, height: 640)

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 44) {
                HeroIcon(module: module, size: 210)
                VStack(alignment: .leading, spacing: 20) {
                    Text(summary.cancelled ? "Stopped" : module.doneTitle)
                        .font(.system(size: 34, weight: .semibold))
                    HStack(spacing: 14) {
                        CategoryBadge(symbol: "checkmark", palette: module.palette, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.doneHeadline(summary))
                                .font(.system(size: 19, weight: .semibold))
                            Text(summary.cancelled ? "\(module.doneSubtitle) before you cancelled" : module.doneSubtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    if !summary.failures.isEmpty {
                        Label("\(summary.failures.count) item\(summary.failures.count == 1 ? "" : "s") couldn't be removed", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.yellow.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 80)
            .frame(maxWidth: 780)
            .overlay(alignment: .bottom) {
                HStack {
                    if !summary.failures.isEmpty {
                        Button("View Log") { showingLog = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(24)
            }
            .glassCard(cornerRadius: 26)
            Spacer()
        }
        .padding(32)
        // Bubbles rise behind the whole card. Fixed size on purpose: sizing them with a
        // GeometryReader stalled the animated switch to this screen in release builds.
        .background {
            BubbleField(tint: module.palette.accent, size: Self.bubbleArea)
                .frame(width: Self.bubbleArea.width, height: Self.bubbleArea.height)
                .allowsHitTesting(false)
        }
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { shown = true }
            if summary.removed > 0, !summary.cancelled { app.celebrate() }
        }
        .sheet(isPresented: $showingLog) {
            FailureLog(failures: summary.failures)
        }
    }
}

private struct FailureLog: View {
    let failures: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items that couldn't be removed").font(.headline)
            Text("Some locations need Full Disk Access (System Settings → Privacy & Security), or the files are in use.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(failures, id: \.self) { Text($0).font(.system(size: 12)).textSelection(.enabled) }
                .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 400)
    }
}
