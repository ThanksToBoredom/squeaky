import SwiftUI

@main
struct SqueakyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var app = AppState()

    var body: some Scene {
        Window("Squeaky", id: "main") {
            RootView()
                .environment(app)
                .onAppear { DebugSnapshot.runIfRequested(app) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            #if DEBUG
            CommandMenu("Debug") {
                // Preview the celebration without removing anything.
                Button("Fire Confetti") { app.celebrate() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            #endif
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
