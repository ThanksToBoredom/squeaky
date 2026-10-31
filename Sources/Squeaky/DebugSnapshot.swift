import AppKit
import ScreenCaptureKit
import SwiftUI

/// Development aid: renders the app's own window to PNG files without needing
/// Screen Recording permission. Only active when `SQUEAKY_SNAPSHOT_DIR` is set.
///
///     SQUEAKY_SNAPSHOT_DIR=/tmp/shots SQUEAKY_SNAPSHOT_SCRIPT="sweep;cleanup:scan;applications" \
///         build/Squeaky.app/Contents/MacOS/Squeaky
///
/// Each `;`-separated step selects a module, optionally starts a scan (`:scan`) or
/// opens the review (`:review`), waits for it to settle and writes `NN-module.png`.
/// `:dump` writes the current results as text to `NN-module.txt` instead.
@MainActor
enum DebugSnapshot {
    /// `cacheDisplay` can't place 3D-transformed layers correctly, so views skip those while snapshotting.
    static let isActive = ProcessInfo.processInfo.environment["SQUEAKY_SNAPSHOT_DIR"] != nil
    /// Snapshot mode normally turns animations off for stable images; set SQUEAKY_SNAPSHOT_ANIMATE
    /// to keep them, e.g. to reproduce animation bugs.
    /// SQUEAKY_SNAPSHOT_HOVER=1 draws hover-only controls as if hovered, for snapshots.
    static let forcesHover = isActive && ProcessInfo.processInfo.environment["SQUEAKY_SNAPSHOT_HOVER"] != nil
    static let disablesAnimations = isActive && ProcessInfo.processInfo.environment["SQUEAKY_SNAPSHOT_ANIMATE"] == nil

    static func runIfRequested(_ app: AppState) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SQUEAKY_SNAPSHOT_DIR"] else { return }
        let steps = (env["SQUEAKY_SNAPSHOT_SCRIPT"] ?? Module.allCases.map(\.rawValue).joined(separator: ";"))
            .split(separator: ";").map(String.init)

        Task {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for (index, step) in steps.enumerated() {
                let parts = step.split(separator: ":").map(String.init)
                guard !parts.isEmpty else { continue }
                if parts[0] == "yara" {
                    // Self-test: compile Apple's XProtect rules and scan the installed apps' executables.
                    var report: [String] = []
                    let resources = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources"
                    let start = Date()
                    let sources = ["XProtect.yara", "XPScripts.yr"].compactMap { name -> (name: String, text: String)? in
                        guard let text = try? String(contentsOfFile: "\(resources)/\(name)", encoding: .utf8) else { return nil }
                        return (name, text)
                    } + [("selftest", "rule SqueakySelfTest { strings: $a = \"SQUEAKY-YARA-SELFTEST\" condition: $a }")]
                    let compiled = YaraRules.compile(sources)
                    report.append("compiled \(compiled.count)/\(sources.count) rule files in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                    compiled.forEach { report += $0.compileErrors }
                    let probe = URL(fileURLWithPath: "\(dir)/probe.txt")
                    try? "hello SQUEAKY-YARA-SELFTEST".write(to: probe, atomically: true, encoding: .utf8)
                    report.append("probe matches: \(compiled.flatMap { $0.matches(file: probe) })")
                    let scanStart = Date()
                    var scanned = 0
                    var hits: [String] = []
                    for app in FileUtils.children(of: URL(fileURLWithPath: "/Applications")) where app.pathExtension == "app" {
                        guard let executable = Bundle(url: app)?.executableURL else { continue }
                        scanned += 1
                        let names = compiled.flatMap { $0.matches(file: executable) }
                        if !names.isEmpty { hits.append("\(executable.path): \(names)") }
                    }
                    report.append("scanned \(scanned) executables in \(String(format: "%.2f", Date().timeIntervalSince(scanStart)))s, matches: \(hits)")
                    try? report.joined(separator: "\n").write(toFile: "\(dir)/\(String(format: "%02d", index))-yara.txt", atomically: true, encoding: .utf8)
                    continue
                }
                if parts[0] == "sweep-run" {
                    // Runs Sweep on the declutter demo data (system files: refused, nothing removed).
                    app.selection = .sweep
                    app.clutter.selection = Set(app.clutter.categories.flatMap { $0.items.map(\.url) })
                    app.sweep.phase = .results
                    try? await Task.sleep(for: .seconds(0.5))
                    app.sweep.run()
                    var log: [String] = []
                    var elapsed = 0.0
                    for moment in [0.5, 4.0, 8.0, 12.0, 16.0] {
                        try? await Task.sleep(for: .seconds(moment - elapsed))
                        elapsed = moment
                        log.append("after \(moment)s: phase = \(String(describing: app.sweep.phase).prefix(30))")
                        snapshot(to: "\(dir)/\(String(format: "%02d", index))-sweep-run-\(moment)s.png")
                    }
                    try? log.joined(separator: "\n").write(toFile: "\(dir)/\(String(format: "%02d", index))-sweep-run.txt", atomically: true, encoding: .utf8)
                    continue
                }
                if parts[0] == "remove-startup", parts.count > 1 {
                    // `remove-startup:<label>` removes that user launch agent via the Performance page's code.
                    await app.performance.inspect()
                    var result = "no user agent labelled \(parts[1])"
                    if let item = app.performance.startupItems.first(where: { $0.label == parts[1] }) {
                        await app.performance.remove(item)
                        let stillListed = app.performance.startupItems.contains { $0.label == parts[1] }
                        result = "file exists: \(FileManager.default.fileExists(atPath: item.plist.path)), still listed: \(stillListed), error: \(app.performance.startupError ?? "none")"
                    }
                    try? result.write(toFile: "\(dir)/\(String(format: "%02d", index))-remove-startup.txt", atomically: true, encoding: .utf8)
                    continue
                }
                if parts[0] == "watch-test" {
                    // A dummy app in /Applications is listed, then deleted behind Squeaky's back;
                    // the folder watcher should drop it from the results without a rescan.
                    let dummy = URL(fileURLWithPath: "/Applications/SqueakyWatchTest.app")
                    try? FileManager.default.createDirectory(at: dummy, withIntermediateDirectories: true)
                    let model = app.applications
                    model.categories = [ScanCategory(id: "all", title: "Applications", description: "", symbol: "app", metric: .count,
                                                     items: [CleanItem(url: dummy, name: "SqueakyWatchTest", size: 0, removal: .trash)])]
                    model.phase = .results
                    let before = model.items().count
                    try? await Task.sleep(for: .seconds(0.5))
                    try? FileManager.default.removeItem(at: dummy)
                    try? await Task.sleep(for: .seconds(2.5))
                    try? "listed before: \(before), after external delete: \(model.items().count), phase: \(model.phase)"
                        .write(toFile: "\(dir)/\(String(format: "%02d", index))-watch-test.txt", atomically: true, encoding: .utf8)
                    continue
                }
                if parts[0] == "size", parts.count > 1 {
                    // `size:1100x1600` resizes the window, e.g. to see the bottom of scrolling pages.
                    let dims = parts[1].split(separator: "x").compactMap { Double($0) }
                    if dims.count == 2, dims.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 16384 }), let window = NSApp.windows.first(where: { $0.isVisible }) {
                        window.setContentSize(NSSize(width: dims[0], height: dims[1]))
                    }
                    continue
                }
                if parts[0] == "celebrate" {
                    // Particles only show up in a real screen capture, so record a short sequence.
                    app.celebrate()
                    var elapsed = 0.0
                    for moment in [0.1, 0.3, 0.6, 1.0, 1.4, 2.0] {
                        try? await Task.sleep(for: .seconds(moment - elapsed))
                        elapsed = moment
                        await capture(to: "\(dir)/\(String(format: "%02d", index))-celebrate-\(String(format: "%.2f", moment))s.png")
                    }
                    continue
                }
                if parts[0] == "permissions" {
                    // `permissions:granted` previews the success state without real access.
                    if parts.count > 1, parts[1] == "granted" { app.hasFullDiskAccess = true }
                    app.showingPermissions = true
                    try? await Task.sleep(for: .seconds(1.2))
                    snapshot(to: "\(dir)/\(String(format: "%02d", index))-\(step.replacingOccurrences(of: ":", with: "-")).png")
                    app.showingPermissions = false
                    continue
                }
                guard let module = Module(rawValue: parts[0]) else { continue }
                app.selection = module
                switch parts.dropFirst().first {
                case "scan":
                    if module == .sweep { app.sweep.start() } else { app.model(for: module)?.startScan() }
                    try? await Task.sleep(for: .seconds(1.2))
                    snapshot(to: "\(dir)/\(String(format: "%02d", index))a-\(step.replacingOccurrences(of: ":", with: "-"))-scanning.png")
                    while app.sweep.phase == .scanning || app.model(for: module)?.phase == .scanning {
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                case "dump":
                    // Text listing of the current results, for checking what scanners matched.
                    if let model = app.model(for: module) {
                        var lines: [String] = []
                        for category in model.categories {
                            lines.append("## \(category.title) (\(category.items.count))")
                            for item in category.items {
                                lines.append("- \(item.name)  \(item.totalSize.formattedBytes)  [\(item.detail ?? "")]")
                                for extra in item.extras { lines.append("    \(extra.url.abbreviatedPath)") }
                                for label in item.launchLabels { lines.append("    launchd: \(label)") }
                            }
                        }
                        try? lines.joined(separator: "\n").write(toFile: "\(dir)/\(String(format: "%02d", index))-\(module.rawValue).txt", atomically: true, encoding: .utf8)
                    }
                    continue
                case "confirm":
                    // `<module>:confirm:<item name>` selects just that item and shows the confirmation
                    // alert, then cancels it. Nothing is removed.
                    if let model = app.model(for: module), parts.count > 2 {
                        let name = parts[2...].joined(separator: ":")
                        model.selection = Set(model.items().filter { $0.name == name }.map(\.url))
                        model.review(nil)
                        model.requestClean()
                        try? await Task.sleep(for: .seconds(1.2))
                        try? (model.pendingClean.map { "\($0.title)\n\($0.message)\nuninstaller: \($0.vendorUninstaller?.url.path ?? "none")" } ?? "nothing selected")
                            .write(toFile: "\(dir)/\(String(format: "%02d", index))-confirm.txt", atomically: true, encoding: .utf8)
                        snapshot(to: "\(dir)/\(String(format: "%02d", index))-confirm.png")
                        model.pendingClean = nil
                    }
                    continue
                case "clean":
                    // Runs a clean on whatever is selected (use after `:demo`, whose system files the
                    // safety check refuses to delete) and records the screen and phase as it finishes.
                    if let model = app.model(for: module) {
                        model.selection = Set(model.categories.flatMap { $0.items.map(\.url) })
                        model.requestClean()
                        if parts.count > 2, parts[2] == "alert" {
                            // Show the confirmation alert first, then confirm it like the button does:
                            // start the clean and dismiss the alert in the same turn of the run loop.
                            try? await Task.sleep(for: .seconds(1))
                            snapshot(to: "\(dir)/\(String(format: "%02d", index))-clean-alert.png")
                        }
                        if parts.count > 2, parts[2] == "click" {
                            // Press the confirmation alert's real button, exactly like a user would.
                            try? await Task.sleep(for: .seconds(1))
                            let buttons = NSApp.windows.flatMap { allButtons(in: $0.contentView) }
                            let verb = model.module.actionVerb
                            if let button = buttons.first(where: { $0.title == verb }) {
                                button.performClick(nil)
                            } else {
                                print("click: no '\(verb)' button among \(buttons.map(\.title))")
                            }
                        } else if let pending = model.pendingClean {
                            model.performClean(pending)
                            model.pendingClean = nil
                        }
                        if parts.count > 2, parts[2] == "cancel" {
                            // Press Cancel shortly after the clean starts (pair with SQUEAKY_SLOW_CLEAN).
                            try? await Task.sleep(for: .seconds(0.3))
                            model.cancelClean()
                        }
                        var log: [String] = []
                        var elapsed = 0.0
                        for moment in [0.5, 2.0, 4.0, 6.0] {
                            try? await Task.sleep(for: .seconds(moment - elapsed))
                            elapsed = moment
                            log.append("after \(moment)s: phase = \(String(describing: model.phase).prefix(30)), done screen appeared: \(app.confettiBursts > 0)")
                            snapshot(to: "\(dir)/\(String(format: "%02d", index))-clean-\(moment)s.png")
                        }
                        try? log.joined(separator: "\n").write(toFile: "\(dir)/\(String(format: "%02d", index))-clean.txt", atomically: true, encoding: .utf8)
                    }
                    continue
                case "demo-real":
                    // Throwaway folders in ~/Library/Caches that a clean really deletes, so the
                    // "something was removed" path (and its confetti) runs.
                    if let model = app.model(for: module) {
                        let items = (1...2).map { n -> CleanItem in
                            let url = FileUtils.library.appendingPathComponent("Caches/squeaky-snapshot-test-\(n)")
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            try? Data(count: 50_000).write(to: url.appendingPathComponent("junk.bin"))
                            return CleanItem(url: url, name: url.lastPathComponent, size: 50_000, removal: .delete)
                        }
                        model.categories = [ScanCategory(id: "test", title: "Test Junk", description: "Throwaway test folders.", symbol: "archivebox.fill", items: items)]
                        model.phase = .results
                    }
                case "demo":
                    // Fake results built from system files, for previewing cards without real data.
                    if let model = app.model(for: module) {
                        let samples = ["/System/Library/Fonts/Helvetica.ttc", "/System/Library/CoreServices/SystemVersion.plist",
                                       "/System/Library/Desktop Pictures", "/usr/share/man"]
                        let items = samples.map { CleanItem(url: URL(fileURLWithPath: $0), name: ($0 as NSString).lastPathComponent,
                                                            size: 120_000_000, removal: .trash, selectedByDefault: false) }
                        model.categories = [
                            ScanCategory(id: SweepModel.duplicatesID, title: "Duplicates", description: "Identical copies of the same file.",
                                         symbol: "doc.on.doc.fill", metric: .count, items: Array(items.prefix(2))),
                            ScanCategory(id: "large", title: "Large Files", description: "Big files.", symbol: "externaldrive.fill", items: items),
                        ]
                        model.phase = .results
                    }
                case "review":
                    app.model(for: module)?.review(parts.count > 2 ? parts[2] : nil)
                default:
                    break
                }
                try? await Task.sleep(for: .seconds(1.2))
                snapshot(to: "\(dir)/\(String(format: "%02d", index))-\(step.replacingOccurrences(of: ":", with: "-")).png")
            }
            if env["SQUEAKY_SNAPSHOT_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }

    /// Captures the window as it appears on screen, including Core Animation particles that
    /// `cacheDisplay` can't see. Needs Screen Recording permission for Squeaky.
    static func capture(to path: String) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                print("capture: window not found")
                return
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target),
                configuration: configuration
            )
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
        } catch {
            print("capture failed: \(error.localizedDescription)")
        }
    }

    private static func allButtons(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        return (view as? NSButton).map { [$0] } ?? [] + view.subviews.flatMap { allButtons(in: $0) }
    }

    static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
