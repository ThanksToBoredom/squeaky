import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    /// `/Users/me/Library/Caches` → `~/Library/Caches`
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Thread-safe "what are we looking at right now" value. Scanners write to it
/// from background threads; the scanning screen polls it on a timer so we don't
/// flood the main actor with updates.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ""

    var path: String { lock.withLock { current } }

    func report(_ path: String) {
        lock.withLock { current = path }
    }
}

enum FileUtils {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library") }

    static func children(of url: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        )) ?? []
        return urls.filter { $0.lastPathComponent != ".DS_Store" }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Bytes actually used on disk by a file or (recursively) a directory.
    static func allocatedSize(of url: URL, reporter: ProgressReporter? = nil) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            count += 1
            if count % 256 == 0 {
                if Task.isCancelled { return total }
                reporter?.report(file.path)
            }
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Last line of defence: we only ever remove things inside the user's home
    /// folder (never the well-known folders themselves) or app bundles in /Applications.
    static func isSafeToRemove(_ url: URL, home: URL = FileUtils.home) -> Bool {
        guard url.isFileURL else { return false }
        // Resolve ancestors, but not the final component: removing a symlink removes
        // the link itself. A symlinked parent, however, redirects the operation.
        let normalized = url.standardizedFileURL
        let path = normalized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(normalized.lastPathComponent).path
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
        let protected: Set<String> = Set([
            "", "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
            "Applications", ".Trash", "Library/Caches", "Library/Logs", "Library/Application Support",
            "Library/Preferences", "Library/Containers", "Library/Group Containers", "Library/Mail",
        ].map { $0.isEmpty ? homePath : "\(homePath)/\($0)" })

        if protected.contains(path) { return false }
        if path.hasPrefix(homePath + "/") { return true }
        if path.hasPrefix("/Applications/"), normalized.pathExtension == "app" {
            // Do not offer nested helper apps independently of their owning app.
            return !URL(fileURLWithPath: path).deletingLastPathComponent().pathComponents
                .contains { $0.hasSuffix(".app") }
        }
        return false
    }

    /// Owned by someone else (usually root, from an installer package) and not writable by us:
    /// moving it to the Trash needs an administrator.
    static func needsAdministrator(_ url: URL) -> Bool {
        guard let owner = (try? FileManager.default.attributesOfItem(atPath: url.path)[.ownerAccountID]) as? NSNumber
        else { return false }
        return owner.uint32Value != getuid() && !FileManager.default.isWritableFile(atPath: url.path)
    }

    static func sha256(of url: URL, limit: Int? = nil) -> String? {
        guard limit.map({ $0 >= 0 }) ?? true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunk = Swift.min(1 << 20, remaining)
            let data: Data
            do { data = try handle.read(upToCount: chunk) ?? Data() }
            catch { return nil }
            if data.isEmpty { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Lets the UI stop a removal that's running on a background thread. Checked between items,
/// so the item being removed when Cancel is pressed still finishes.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

struct RemovalRequest: Sendable {
    let url: URL
    let extras: [URL]
    var launchLabels: [String] = []
    let size: Int64
    let method: RemovalMethod
}

enum FileOps {
    /// Removes the requests in order, reporting "Removing 3 of 40: <path>" to `reporter` as it goes.
    static func remove(_ requests: [RemovalRequest], reporter: ProgressReporter? = nil, cancel: CancelToken? = nil) -> CleanSummary {
        let fm = FileManager.default
        var summary = CleanSummary()
        var seen = Set<URL>()

        for (index, request) in requests.enumerated() where seen.insert(request.url).inserted {
            if cancel?.isCancelled == true {
                summary.cancelled = true
                break
            }
            reporter?.report("Removing \(index + 1) of \(requests.count): \(request.url.abbreviatedPath)")
            if request.url.pathExtension == "app",
               let bundleID = Bundle(url: request.url)?.bundleIdentifier,
               !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                summary.failures.append("\(request.url.lastPathComponent): quit the app before removing it.")
                continue
            }

            for label in request.launchLabels {
                launchctl(["bootout", "gui/\(getuid())/\(label)"])
            }

            var ok = true
            for url in [request.url] + request.extras {
                let isPrimary = url == request.url
                guard FileUtils.isSafeToRemove(url) else {
                    summary.failures.append("\(url.abbreviatedPath): refused, outside of allowed locations.")
                    if isPrimary { ok = false }
                    continue
                }
                // attributesOfItem doesn't follow symlinks, so dangling links still count as present.
                guard (try? fm.attributesOfItem(atPath: url.path)) != nil else { continue }
                unloadUserLaunchAgent(url)
                // Apps installed by a package are owned by root. Finder can move those to the
                // Trash after asking for an administrator password; Squeaky itself can't.
                if isPrimary, request.method == .trash, url.pathExtension == "app", FileUtils.needsAdministrator(url) {
                    if let error = trashWithFinder(url) {
                        summary.failures.append("\(url.abbreviatedPath): \(error)")
                        ok = false
                    }
                    continue
                }
                do {
                    switch request.method {
                    case .trash: try fm.trashItem(at: url, resultingItemURL: nil)
                    case .delete: try fm.removeItem(at: url)
                    }
                } catch {
                    summary.failures.append("\(url.abbreviatedPath): \(error.localizedDescription)")
                    if isPrimary { ok = false }
                }
            }
            if ok {
                summary.freed += request.size
                summary.removed += 1
                summary.removedURLs.append(request.url)
            }
        }
        return summary
    }

    /// Asks Finder to move `url` to the Trash; Finder prompts for an administrator password when
    /// needed. Returns an error message, or nil on success. The path is passed as an argument,
    /// never spliced into the script.
    private static func trashWithFinder(_ url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "with timeout of 600 seconds",
            "-e", "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)",
            "-e", "end timeout",
            "-e", "end run",
            url.path,
        ]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do { try process.run() } catch { return error.localizedDescription }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        if message.contains("-128") { return "cancelled in Finder." }
        if message.contains("-1743") {
            return "Squeaky isn't allowed to control Finder. Allow it in System Settings → Privacy & Security → Automation."
        }
        return "Finder couldn't move it to the Trash. Try dragging it to the Trash yourself."
    }

    /// A launch agent that's still loaded keeps running (and may be restarted), so unload it first.
    private static func unloadUserLaunchAgent(_ url: URL) {
        let agents = FileUtils.library.appendingPathComponent("LaunchAgents").standardizedFileURL.path
        guard url.pathExtension == "plist",
              url.deletingLastPathComponent().standardizedFileURL.path == agents
        else { return }
        launchctl(["bootout", "gui/\(getuid())", url.path])
    }

    /// Runs launchctl in the user's own domain. Failures (e.g. the job isn't loaded) are expected and ignored.
    private static func launchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    static func icon(for type: UTType) -> NSImage {
        let key = "type:\(type.identifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        cache.setObject(image, forKey: key)
        return image
    }
}
