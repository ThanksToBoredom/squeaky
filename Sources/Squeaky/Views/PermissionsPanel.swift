import SwiftUI

/// Onboarding card asking for Full Disk Access, shown over the current module.
struct PermissionsPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let palette = app.selection.palette
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { app.dismissPermissions() }

            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 22) {
                    CategoryBadge(symbol: "lock.shield.fill", palette: palette, size: 64)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Give Squeaky Full Disk Access")
                            .font(.system(size: 26, weight: .semibold))
                        Text("macOS keeps some folders private until you allow access. With Full Disk Access, Squeaky can see the Trash, Mail attachments and app containers, and remove apps completely.")
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    Step(number: 1, text: "Open **Privacy & Security → Full Disk Access** in System Settings.")
                    Step(number: 2, text: "Turn on **Squeaky**. If it isn't listed, click **+** and choose Squeaky, or drag it in from Finder.")
                    Step(number: 3, text: "Choose **Quit & Reopen** if macOS asks. You only need to do this once.")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))

                Group {
                    if app.hasFullDiskAccess {
                        Label("Full Disk Access is on. Scan again to include protected folders.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color(hex: 0xC4F5D0))
                    } else if app.openedPermissionSettings {
                        Label("Waiting for access… If you've already turned it on, relaunch Squeaky.", systemImage: "hourglass")
                            .foregroundStyle(Color.yellow.opacity(0.9))
                    } else {
                        Label("Not granted yet", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.yellow.opacity(0.9))
                    }
                }
                .font(.system(size: 13, weight: .regular))
                .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    if app.hasFullDiskAccess {
                        Spacer()
                        Button("Done") { app.dismissPermissions() }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Not Now") { app.dismissPermissions() }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Button("Show Squeaky in Finder") { Permissions.revealAppInFinder() }
                            .buttonStyle(GlassButtonStyle())
                        Button("Open System Settings") {
                            app.openedPermissionSettings = true
                            Permissions.openFullDiskAccessSettings()
                        }
                        .buttonStyle(GlassButtonStyle(prominent: !app.openedPermissionSettings))
                        if app.openedPermissionSettings {
                            Button("Relaunch Squeaky") { Permissions.relaunch() }
                                .buttonStyle(GlassButtonStyle(prominent: true))
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(.top, 24)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .frame(width: 720)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .glassCard(cornerRadius: 26)
            .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
        }
        // System Settings doesn't hand focus back to Squeaky, so keep checking while the card is open.
        .task {
            while !Task.isCancelled, !app.hasFullDiskAccess {
                try? await Task.sleep(for: .seconds(1.5))
                app.refreshPermissions()
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.18)))
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
