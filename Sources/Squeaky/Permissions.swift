import AppKit

/// Full Disk Access can't be requested programmatically: the user has to switch it on in
/// System Settings. Once granted it persists for as long as the app's code signature stays the same.
enum Permissions {
    /// Probes files that only an app with Full Disk Access can read.
    static var hasFullDiskAccess: Bool {
        let home = FileUtils.home
        let tccDatabase = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = try? FileHandle(forReadingFrom: tccDatabase) {
            try? handle.close()
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Safari").path)) != nil
    }

    static func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    /// macOS may only apply a new grant after a restart, so offer to relaunch.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            guard application != nil, error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Lets the user drag Squeaky into the Full Disk Access list if it isn't there yet.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
