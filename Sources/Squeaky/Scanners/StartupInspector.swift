import Foundation

/// A launch agent or daemon: something that starts on its own in the background.
struct StartupItem: Identifiable, Sendable {
    enum Domain: String, Sendable {
        case user = "User agent"
        case systemAgent = "System-wide agent"
        case daemon = "System daemon"
    }

    let label: String
    let program: String?
    let plist: URL
    let domain: Domain
    let isDisabled: Bool
    /// When it runs: "At login", "Keep alive", "Every 3600 seconds", …
    let triggers: [String]
    let programExists: Bool

    var id: String { plist.path }

    /// The app it belongs to, if its program lives inside an app bundle (used for the icon).
    var appPath: String? { program.flatMap(SystemSampler.appBundlePath(for:)) }
}

/// A local APFS snapshot on the startup disk, as listed by `tmutil`.
struct LocalSnapshot: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case timeMachine = "Time Machine"
        case systemUpdate = "System update"
        case other = "Local snapshot"
    }

    let identifier: String
    let kind: Kind
    let date: Date?
    /// `yyyy-MM-dd-HHmmss`, only for Time Machine snapshots: the only kind that may be deleted.
    let deletionTimestamp: String?

    var id: String { identifier }
}

enum StartupInspector {
    private static let folders: [(String, StartupItem.Domain)] = [
        (FileUtils.library.appendingPathComponent("LaunchAgents").path, .user),
        ("/Library/LaunchAgents", .systemAgent),
        ("/Library/LaunchDaemons", .daemon),
    ]

    /// Launch agents and daemons outside the macOS system folders, plus anything that couldn't be read.
    static func startupItems() -> (items: [StartupItem], issues: [String]) {
        var items: [StartupItem] = []
        var issues: [String] = []
        for (folder, domain) in folders {
            let url = URL(fileURLWithPath: folder)
            guard FileManager.default.fileExists(atPath: folder) else { continue }
            for plist in FileUtils.children(of: url) where plist.pathExtension.lowercased() == "plist" {
                guard let dictionary = NSDictionary(contentsOf: plist) as? [String: Any] else {
                    issues.append("Couldn't read \(plist.abbreviatedPath)")
                    continue
                }
                items.append(item(from: dictionary, plist: plist, domain: domain))
            }
        }
        let order: [StartupItem.Domain] = [.user, .systemAgent, .daemon]
        items.sort {
            $0.domain == $1.domain
                ? $0.label.localizedStandardCompare($1.label) == .orderedAscending
                : order.firstIndex(of: $0.domain)! < order.firstIndex(of: $1.domain)!
        }
        return (items, issues)
    }

    private static func item(from plist: [String: Any], plist url: URL, domain: StartupItem.Domain) -> StartupItem {
        let arguments = (plist["ProgramArguments"] as? [String]) ?? (plist["BundleProgramArguments"] as? [String]) ?? []
        let program = (plist["Program"] as? String) ?? (plist["BundleProgram"] as? String) ?? arguments.first
        let expanded = program.map { ($0 as NSString).expandingTildeInPath }

        var triggers: [String] = []
        if (plist["RunAtLoad"] as? Bool) == true { triggers.append("At login") }
        if let keepAlive = plist["KeepAlive"] {
            if (keepAlive as? Bool) == true {
                triggers.append("Keep alive")
            } else if let conditions = keepAlive as? [String: Any], !conditions.isEmpty {
                triggers.append("Kept alive when needed")
            }
        }
        if let interval = (plist["StartInterval"] as? NSNumber)?.intValue, interval > 0 {
            triggers.append(interval % 3600 == 0 ? "Every \(interval / 3600) h" : interval % 60 == 0 ? "Every \(interval / 60) min" : "Every \(interval) s")
        }
        if plist["StartCalendarInterval"] != nil { triggers.append("Scheduled") }
        if !((plist["WatchPaths"] as? [String]) ?? []).isEmpty { triggers.append("Watches files") }
        if !((plist["QueueDirectories"] as? [String]) ?? []).isEmpty { triggers.append("Watches folders") }
        if plist["MachServices"] != nil, triggers.isEmpty { triggers.append("On demand") }

        return StartupItem(
            label: (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            program: expanded,
            plist: url,
            domain: domain,
            isDisabled: (plist["Disabled"] as? Bool) == true,
            triggers: triggers,
            // Bundled programs (BundleProgram) are relative paths inside an app; treat those as present.
            programExists: expanded.map { !$0.hasPrefix("/") || FileManager.default.fileExists(atPath: $0) } ?? true
        )
    }

    // MARK: - Snapshots

    static func snapshots() -> (snapshots: [LocalSnapshot], issues: [String]) {
        let result = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        guard result.status == 0 else {
            return ([], ["Couldn't list local snapshots: \(result.error.isEmpty ? "tmutil failed" : result.error)"])
        }
        let snapshots = result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Snapshots for") }
            .map { identifier -> LocalSnapshot in
                let timestamp = timeMachineTimestamp(identifier)
                let kind: LocalSnapshot.Kind = identifier.hasPrefix("com.apple.TimeMachine.") ? .timeMachine
                    : identifier.hasPrefix("com.apple.os.update-") ? .systemUpdate : .other
                return LocalSnapshot(identifier: identifier, kind: kind, date: timestamp.flatMap(parse), deletionTimestamp: timestamp)
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return (snapshots, [])
    }

    /// Deletes one Time Machine snapshot. Refuses anything else (system update snapshots etc.).
    static func delete(_ snapshot: LocalSnapshot) throws {
        guard snapshot.kind == .timeMachine, let timestamp = snapshot.deletionTimestamp else {
            throw NSError(domain: "Squeaky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only Time Machine snapshots can be deleted."])
        }
        let result = run("/usr/bin/tmutil", ["deletelocalsnapshots", timestamp])
        guard result.status == 0 else {
            throw NSError(domain: "Squeaky", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.error.isEmpty ? "tmutil exited with status \(result.status)." : result.error,
            ])
        }
    }

    /// `com.apple.TimeMachine.2026-10-08-101500.local` → `2026-10-08-101500`, validated.
    private static func timeMachineTimestamp(_ identifier: String) -> String? {
        let prefix = "com.apple.TimeMachine.", suffix = ".local"
        guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else { return nil }
        let timestamp = String(identifier.dropFirst(prefix.count).dropLast(suffix.count))
        return parse(timestamp) == nil ? nil : timestamp
    }

    private static func parse(_ timestamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.isLenient = false
        guard let date = formatter.date(from: timestamp), formatter.string(from: date) == timestamp else { return nil }
        return date
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: out, as: UTF8.self),
            String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
