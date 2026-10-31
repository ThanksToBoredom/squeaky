import Foundation
import Security

/// Malware scan built on Apple's own definitions (see `XProtectCatalog`):
///
/// - YARA rules from XProtect against app executables, launch-item programs and loose
///   executables/scripts in the usual drop folders;
/// - Gatekeeper's blocklist of revoked code hashes and developer teams;
/// - XProtect's list of blocked Safari extensions;
/// - launch items that look out of place (missing or unsigned program, hidden location),
///   listed for review rather than flagged as malware.
///
/// Runs without root, so system folders that only root can read are skipped.
enum ProtectionScanner {
    /// What the last scan covered, for the results screen.
    struct Summary: Sendable {
        var filesScanned = 0
        var catalogVersion: Int?
        var catalogUpdated: Date?
        var issues: [String] = []
        var incomplete: Bool { catalogVersion == nil || !issues.isEmpty }
        var status: String { incomplete ? "Protection scan incomplete" : "No malware found in scanned files" }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedSummary = Summary()
    static var lastSummary: Summary { lock.withLock { storedSummary } }

    static let threatsID = "threats"
    static let launchItemsID = "launch-items"

    /// Larger files are skipped: real malware binaries are small, and huge app binaries make the scan slow.
    private static let maxFileSize: Int64 = 150 * 1024 * 1024

    /// A file to scan, and the item (app bundle or the file itself) to remove if it matches.
    private struct Target: Hashable {
        let file: URL
        let owner: URL
    }

    private struct LaunchItem {
        let plist: URL
        let program: URL?
    }

    static func scan(_ reporter: ProgressReporter) async -> [ScanCategory] {
        guard let catalog = XProtectCatalog.load() else {
            lock.withLock { storedSummary = Summary() }
            return []
        }
        var sources = catalog.yaraSources
        #if DEBUG
        // End-to-end test without real malware: flags files containing a marker string.
        if ProcessInfo.processInfo.environment["SQUEAKY_TEST_RULE"] != nil {
            sources.append(("selftest", #"rule SqueakySelfTest { meta: description = "Squeaky self-test marker" strings: $a = "SQUEAKY-YARA-SELFTEST" condition: $a }"#))
        }
        #endif
        let descriptions = catalog.ruleDescriptions(in: sources)
        let rules = YaraRules.compile(sources)
        var issues: [String] = []
        if sources.isEmpty || rules.count != sources.count {
            issues.append("Some XProtect rule files could not be compiled.")
        }
        let blocklist = catalog.gatekeeperBlocklist()
        let blockedExtensions = Set(catalog.blockedSafariExtensions.map { "\($0.bundleID)|\($0.team)" })

        // 1. Collect what to scan.
        let apps = installedApps() + loose(apps: true)
        let launchItems = self.launchItems()
        var targets = apps.flatMap { app in executables(in: app).map { Target(file: $0, owner: app) } }
        targets += launchItems.compactMap { item in
            guard let program = item.program, isScannable(program) else { return nil }
            return Target(file: program, owner: appBundle(containing: program) ?? program)
        }
        targets += loose(apps: false).map { Target(file: $0, owner: $0) }
        targets = Array(Set(targets))
        if Task.isCancelled { return [] }

        // 2. YARA, in parallel (libyara allows concurrent scans with the same compiled rules).
        var findings: [URL: [String]] = [:]
        let findingsLock = NSLock()
        var completedFiles = 0
        var failedFiles = 0
        let chunks = stride(from: 0, to: targets.count, by: 16).map { Array(targets[$0..<min($0 + 16, targets.count)]) }
        let cancellation = CancelToken()
        await withTaskCancellationHandler {
        DispatchQueue.concurrentPerform(iterations: chunks.count) { index in
            for target in chunks[index] {
                if cancellation.isCancelled { return }
                reporter.report(target.file.path)
                let scans = rules.map { $0.scan(file: target.file) }
                findingsLock.withLock {
                    if !scans.isEmpty && scans.allSatisfy({ $0.completed }) { completedFiles += 1 }
                    else { failedFiles += 1 }
                }
                let names = scans.flatMap(\.names)
                guard !names.isEmpty else { continue }
                let reasons = names.map { "Matches XProtect signature \(descriptions[$0] ?? $0)" }
                findingsLock.withLock { findings[target.owner, default: []] += reasons }
            }
        }
        } onCancel: {
            cancellation.cancel()
        }
        if Task.isCancelled { return [] }

        // 3. Gatekeeper's blocklist and blocked Safari extensions.
        for owner in Set(targets.map(\.owner)) {
            if Task.isCancelled { return [] }
            let signing = SigningInfo(owner)
            if let team = signing.teamID, blocklist.teams.contains(team) {
                findings[owner, default: []].append("Signed by a developer Apple has blocked (\(team))")
            } else if let hash = signing.cdhash, blocklist.hashes.contains(hash) {
                findings[owner, default: []].append("Blocked by Gatekeeper")
            }
        }
        for app in apps {
            for plugin in FileUtils.children(of: app.appendingPathComponent("Contents/PlugIns")) where plugin.pathExtension == "appex" {
                guard let bundleID = Bundle(url: plugin)?.bundleIdentifier,
                      let team = SigningInfo(plugin).teamID,
                      blockedExtensions.contains("\(bundleID)|\(team)")
                else { continue }
                findings[app, default: []].append("Contains a Safari extension Apple blocks (\(bundleID))")
            }
        }

        // 4. Launch items: ones pointing at a threat go with it; odd-looking ones are listed for review.
        var review: [CleanItem] = []
        for item in launchItems {
            if let program = item.program, let owner = findings.keys.first(where: { owns(program: program, owner: $0) }) {
                findings[owner, default: []].append("Starts automatically (\(item.plist.lastPathComponent))")
                continue
            }
            let reasons = suspicion(of: item)
            guard !reasons.isEmpty else { continue }
            let removable = FileUtils.isSafeToRemove(item.plist)
            review.append(CleanItem(
                url: item.plist,
                name: item.plist.deletingPathExtension().lastPathComponent,
                size: FileUtils.allocatedSize(of: item.plist),
                detail: (reasons + [removable ? nil : "needs an administrator to remove"].compactMap { $0 }).joined(separator: " · "),
                removal: .trash,
                selectedByDefault: false
            ))
        }

        let threats = findings.map { owner, reasons in
            var seen = Set<String>()
            let launchPlists = launchItems
                .filter { $0.program.map { owns(program: $0, owner: owner) } ?? false }
                .map { ExtraFile(url: $0.plist, size: FileUtils.allocatedSize(of: $0.plist)) }
                .filter { FileUtils.isSafeToRemove($0.url) }
            return CleanItem(
                url: owner,
                name: owner.lastPathComponent,
                size: FileUtils.allocatedSize(of: owner, reporter: reporter),
                detail: reasons.filter { seen.insert($0).inserted }.joined(separator: " · "),
                extras: launchPlists,
                removal: .trash
            )
        }

        if failedFiles > 0 { issues.append("\(failedFiles) files could not be fully scanned.") }
        lock.withLock {
            storedSummary = Summary(filesScanned: completedFiles, catalogVersion: catalog.version, catalogUpdated: catalog.updated, issues: issues)
        }

        return [
            ScanCategory(
                id: threatsID,
                title: "Threats",
                description: "Matched Apple's XProtect malware signatures or Gatekeeper's blocklist. They're moved to the Trash, along with any launch items that start them.",
                symbol: "ladybug.fill",
                metric: .count,
                items: threats.sorted { $0.name < $1.name }
            ),
            ScanCategory(
                id: launchItemsID,
                title: "Suspicious Launch Items",
                description: "Background items that start automatically and look out of place. They're not known malware; review them before removing.",
                symbol: "exclamationmark.triangle.fill",
                metric: .count,
                items: review.sorted { $0.name < $1.name }
            ),
        ]
    }

    static func owns(program: URL, owner: URL) -> Bool {
        let programPath = program.standardizedFileURL.path
        let ownerPath = owner.standardizedFileURL.path
        return programPath == ownerPath || programPath.hasPrefix(ownerPath + "/")
    }

    // MARK: - Targets

    private static func installedApps() -> [URL] {
        var apps: [URL] = []
        for dir in [URL(fileURLWithPath: "/Applications"), FileUtils.home.appendingPathComponent("Applications")] {
            for url in FileUtils.children(of: dir) {
                if url.pathExtension == "app" {
                    apps.append(url)
                } else if FileUtils.isDirectory(url) {
                    apps += FileUtils.children(of: url).filter { $0.pathExtension == "app" }
                }
            }
        }
        return apps
    }

    /// The executables inside an app worth scanning: the main binary, helpers, login items,
    /// XPC services and extensions. Frameworks are skipped; malware lives in the app's own code.
    private static func executables(in app: URL) -> [URL] {
        let contents = app.appendingPathComponent("Contents")
        var files = FileUtils.children(of: contents.appendingPathComponent("MacOS"))
        files += FileUtils.children(of: contents.appendingPathComponent("Library/LaunchServices"))
        for folder in ["Library/LoginItems", "XPCServices", "PlugIns", "Helpers"] {
            for bundle in FileUtils.children(of: contents.appendingPathComponent(folder)) {
                files += FileUtils.children(of: bundle.appendingPathComponent("Contents/MacOS"))
            }
        }
        return files.filter(isScannable)
    }

    /// Where downloaded and dropped malware usually sits. Returns app bundles or loose
    /// executables/scripts, depending on `apps`.
    private static func loose(apps wantApps: Bool) -> [URL] {
        let home = FileUtils.home
        let roots: [(URL, Int)] = [
            (home.appendingPathComponent("Downloads"), 3), (home.appendingPathComponent("Desktop"), 3),
            (home.appendingPathComponent("Documents"), 3), (home.appendingPathComponent("Library/Application Support"), 2),
            (URL(fileURLWithPath: "/Users/Shared"), 3), (URL(fileURLWithPath: "/private/tmp"), 2),
            (URL(fileURLWithPath: "/private/var/tmp"), 2),
        ]
        var found: [URL] = []
        for (root, depth) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey, .fileSizeKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            var visited = 0
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited > 50_000 || Task.isCancelled { break }
                if enumerator.level > depth { enumerator.skipDescendants(); continue }
                if url.pathExtension == "app" {
                    if wantApps { found.append(url) }
                } else if !wantApps, isScannable(url) {
                    found.append(url)
                }
            }
        }
        return found
    }

    private static func launchItems() -> [LaunchItem] {
        let folders = [
            FileUtils.library.appendingPathComponent("LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons"),
        ]
        return folders.flatMap { FileUtils.children(of: $0) }
            .filter { $0.pathExtension == "plist" }
            .map { plist in
                let dict = NSDictionary(contentsOf: plist)
                let path = dict?["Program"] as? String ?? (dict?["ProgramArguments"] as? [String])?.first
                return LaunchItem(plist: plist, program: path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
            }
    }

    private enum FileKind { case machO, script }

    /// Small enough to scan, and a Mach-O binary or a script.
    private static func isScannable(_ url: URL) -> Bool { kind(of: url) != nil }

    private static func kind(of url: URL) -> FileKind? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size > 0, Int64(size) <= maxFileSize,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { return nil }
        let magic = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let machO: Set<UInt32> = [0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA]
        if machO.contains(magic) { return .machO }
        if header.starts(with: [0x23, 0x21]) { return .script } // "#!"
        return nil
    }

    private static func appBundle(containing url: URL) -> URL? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: - Heuristics

    private static func suspicion(of item: LaunchItem) -> [String] {
        guard let program = item.program else { return [] }
        var reasons: [String] = []
        if !FileManager.default.fileExists(atPath: program.path) {
            reasons.append("Its program no longer exists")
        } else {
            let path = program.standardizedFileURL.path
            let temporary = ["/tmp/", "/private/tmp/", "/private/var/tmp/", "/var/tmp/", "/Users/Shared/"]
            if temporary.contains(where: path.hasPrefix) || program.pathComponents.contains(where: { $0.hasPrefix(".") && $0.count > 1 }) {
                reasons.append("Runs from a hidden or temporary folder")
            }
            // Scripts are never signed, so only binaries count.
            if kind(of: program) == .machO, !SigningInfo(program).isSigned {
                reasons.append("Its program isn't code-signed")
            }
        }
        return reasons
    }
}

/// Code-signing facts for a file or bundle, without verifying the whole bundle (which is slow).
struct SigningInfo {
    let teamID: String?
    let cdhash: Data?
    var isSigned: Bool { cdhash != nil }

    init(_ url: URL) {
        var code: SecStaticCode?
        var info: CFDictionary?
        if SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code {
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        }
        let dict = info as? [String: Any] ?? [:]
        teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        cdhash = dict[kSecCodeInfoUnique as String] as? Data
    }
}
