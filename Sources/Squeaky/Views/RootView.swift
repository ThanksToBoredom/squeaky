import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            ModuleBackground(palette: app.selection.palette)
                .id(app.selection)
                .transition(.opacity)

            HStack(spacing: 0) {
                SidebarView()
                content
                    .id(app.selection)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if app.confettiBursts > 0 {
                // A new identity per burst restarts the emitter.
                GeometryReader { proxy in
                    ConfettiBurst(size: proxy.size)
                }
                .id(app.confettiBursts)
                .allowsHitTesting(false)
            }

            if app.showingPermissions {
                PermissionsPanel()
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 660)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .transaction { if DebugSnapshot.disablesAnimations { $0.animation = nil } }
        .onAppear { if !DebugSnapshot.isActive { app.promptForPermissionsIfNeeded() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
            app.refreshAfterExternalChanges()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.selection {
        case .sweep:
            SweepScreen(model: app.sweep)
        case .cleanup, .protection, .applications, .declutter:
            if let model = app.model(for: app.selection) {
                ModuleScreen(model: model)
            }
        case .performance:
            PerformanceScreen(model: app.performance)
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Module.allCases) { module in
                SidebarButton(module: module, selected: app.selection == module, badge: app.badge(for: module)) {
                    withAnimation(.easeInOut(duration: 0.35)) { app.selection = module }
                }
            }
            Spacer()
            PermissionsButton()
        }
        .padding(.top, 70)
        .padding(.bottom, 20)
        .frame(width: 84)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(.vertical, 56)
        }
    }
}

/// Bottom of the sidebar: shows whether Squeaky has Full Disk Access and reopens the onboarding card.
private struct PermissionsButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button {
            app.refreshPermissions()
            withAnimation(.easeInOut(duration: 0.25)) { app.showingPermissions = true }
        } label: {
            Image(systemName: app.hasFullDiskAccess ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 48, height: 48)
                .overlay(alignment: .topTrailing) {
                    if !app.hasFullDiskAccess {
                        Circle().fill(Color.orange).frame(width: 10, height: 10).offset(x: -6, y: 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.hasFullDiskAccess ? "Full Disk Access is on" : "Give Squeaky Full Disk Access")
    }
}

private struct SidebarButton: View {
    let module: Module
    let selected: Bool
    let badge: AppState.Badge
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            SymbolImage(name: module.symbol, size: 19)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.78))
                .frame(width: 48, height: 48)
                .background {
                    if selected || hovering {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(selected ? 0.2 : 0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(selected ? 0.3 : 0.1)))
                            .shadow(color: .black.opacity(selected ? 0.2 : 0), radius: 8, y: 4)
                    }
                }
                .overlay(alignment: .topTrailing) { badgeView.offset(x: 4, y: -4) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(module.title)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var badgeView: some View {
        switch badge {
        case .none:
            EmptyView()
        case .results:
            Circle().fill(.white).frame(width: 10, height: 10).shadow(color: .white.opacity(0.8), radius: 4)
        case .busy:
            ProgressView().controlSize(.mini).tint(.white)
        }
    }
}
