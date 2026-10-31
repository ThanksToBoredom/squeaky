import AppKit
import CoreServices
import Foundation
import Security

/// Lists installed apps together with the support files they've spread around
/// ~/Library, and finds leftovers from apps that are already gone.
enum AppScanner {
    static let unusedAfter: TimeInterval = 90 * 24 * 60 * 60

    /// ~/Library subfolders where apps keep per-app data.
    private static let leftoverFolders = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
        "Saved Application State", "Logs", "HTTPStorages", "WebKit", "Cookies", "Application Scripts",
        "LaunchAgents", "Internet Plug-Ins", "QuickLook", "Spotlight", "PreferencePanes", "Services",
    ]

    /// Folders we consider when looking for orphans. Deliberately narrower than above.
    private static let orphanFolders: Set<String> = [
        "Application Support", "Caches", "Preferences", "ByHost", "Containers",
        "Saved Application State", "HTTPStorages", "WebKit", "LaunchAgents",
    ]

    /// Crash, hang and spin reports are named after the app's executable.
    private static let diagnosticFolders = ["Logs/DiagnosticReports", "Logs/DiagnosticReports/Retired"]
    private static let diagnosticExtensions: Set<String> = ["ips", "crash", "diag", "spin", "hang"]

    /// Plug-ins are matched by their own bundle identifier rather than their file name.
    private static let pluginExtensions: Set<String> = [
        "qlgenerator", "mdimporter", "prefpane", "plugin", "bundle", "service", "appex", "workflow",
    ]

    /// Where apps keep helpers and extensions that have their own bundle identifiers.
    private static let embeddedFolders = [
        "PlugIns", "XPCServices", "Library/LoginItems", "Library/LaunchServices", "Helpers", "Frameworks",
    ]

    /// Identifiers shared by many unrelated apps (frameworks they bundle), never used for matching.
    private static let sharedIdentifierPrefixes = [
        "com.apple.", "org.sparkle-project.", "com.github.electron", "com.electron.", "com.google.chrome.framework",
    ]

    private static let neverRemovable: Set<String> = ["com.apple.Safari"]

    /// A ~/Library entry and what it could be matched by.
    private struct LibraryEntry {
        let url: URL
        /// Lower-cased names: file name without known suffixes and prefixes, a plug-in's bundle ID,
        /// a launch agent's label, or a UUID-named container's owner.
        let identifiers: [String]
        /// For launch agents: the program launchd runs.
        let program: String?
    }

    /// Everything an installed app can be recognised by.
    private struct AppRecord {
        let url: URL
        let bundleID: String
        let name: String
        let executable: String?
        /// The app's own ID plus the IDs of its embedded helpers and extensions, lower-cased.
        var identifiers: [String]
        /// App groups from the app's entitlements, lower-cased. Matched exactly.
        var appGroups: Set<String>
        /// launchd labels of the app's login items and bundled agents, stopped before removal.
        let launchLabels: [String]
    }

    static func scan(_ reporter: ProgressReporter) async -> [ScanCategory] {
        let home = FileUtils.home
        let library = FileUtils.library
        let ownBundleID = Bundle.main.bundleIdentifier

        var bundles: [URL] = []
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for url in FileUtils.children(of: dir) {
                if url.pathExtension == "app" {
                    bundles.append(url)
                } else if FileUtils.isDirectory(url) {
                    bundles += FileUtils.children(of: url).filter { $0.pathExtension == "app" }
                }
            }
        }

        let libraryEntries = leftoverFolders
            .flatMap { FileUtils.children(of: library.appendingPathComponent($0)) }
            .map(libraryEntry(for:))
        let systemEntries = systemLaunchEntries()
        let diagnosticReports = diagnosticFolders
            .flatMap { FileUtils.children(of: library.appendingPathComponent($0)) }
            .filter { diagnosticExtensions.contains($0.pathExtension.lowercased()) }

        // Pass 1: describe every installed app and collect what each one claims.
        var records: [AppRecord] = []
        var installedIDs = Set<String>()
        for url in bundles {
            if Task.isCancelled { return [] }
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            installedIDs.insert(bundleID.lowercased())
            guard !neverRemovable.contains(bundleID), bundleID != ownBundleID else { continue }
            reporter.report(url.path)
            records.append(AppRecord(
                url: url,
                bundleID: bundleID,
                name: url.deletingPathExtension().lastPathComponent,
                executable: bundle.executableURL?.lastPathComponent,
                identifiers: [bundleID.lowercased()] + embeddedIdentifiers(in: url),
                appGroups: Set(applicationGroups(of: url)),
                launchLabels: launchLabels(in: url)
            ))
        }

        // Helper IDs and app groups shared by several installed apps can't tell them apart, so drop them.
        let sharedIdentifiers = duplicates(records.map { Set($0.identifiers.dropFirst()) })
        let sharedGroups = duplicates(records.map(\.appGroups))
        for index in records.indices {
            records[index].identifiers = [records[index].identifiers[0]]
                + records[index].identifiers.dropFirst().filter { !sharedIdentifiers.contains($0) }
            records[index].appGroups.subtract(sharedGroups)
        }

        var claims: [[URL]] = []
        var claimCount: [URL: Int] = [:]
        for record in records {
            var matched = libraryEntries.filter { belongs($0, to: record) }.map(\.url)
            if let executable = record.executable {
                matched += diagnosticReports.filter {
                    let file = $0.lastPathComponent
                    return file.hasPrefix(executable + "-") || file.hasPrefix(executable + "_")
                }
            }
            claims.append(matched)
            for url in Set(matched) { claimCount[url, default: 0] += 1 }
        }

        // Pass 2: build the items. Files claimed by more than one installed app (two copies of
        // the same app, or a vendor's shared folder) are kept, so the other app keeps working.
        let cutoff = Date().addingTimeInterval(-unusedAfter)
        let relative = RelativeDateTimeFormatter()
        var apps: [CleanItem] = []
        var unused: [CleanItem] = []

        for (record, matched) in zip(records, claims) {
            if Task.isCancelled { return [] }
            reporter.report(record.url.path)
            let unique = Array(Set(matched))
            let owned = unique.filter { claimCount[$0] == 1 }
            let sharedCount = unique.count - owned.count

            let extras = owned
                .map { ExtraFile(url: $0, size: FileUtils.allocatedSize(of: $0, reporter: reporter)) }
                .sorted { $0.size > $1.size }

            let usage = usageInfo(for: record.url)
            var detail = if let lastUsed = usage.lastUsed {
                "Last opened \(relative.localizedString(for: lastUsed, relativeTo: Date()))"
            } else {
                "Never opened"
            }
            if !extras.isEmpty {
                detail += " · \(extras.count) support file\(extras.count == 1 ? "" : "s")"
            }
            if sharedCount > 0 {
                detail += " · \(sharedCount) shared kept"
            }
            let components = systemComponents(of: record, in: systemEntries)
            let uninstaller = vendorUninstaller(for: record, components: components)
            let needsAdministrator = FileUtils.needsAdministrator(record.url)
            if !components.isEmpty {
                detail += " · \(components.count) system part\(components.count == 1 ? "" : "s") stay\(components.count == 1 ? "s" : "")"
            }

            let item = CleanItem(
                url: record.url, name: record.name,
                size: FileUtils.allocatedSize(of: record.url, reporter: reporter), detail: detail,
                extras: extras, launchLabels: record.launchLabels, removal: .trash, selectedByDefault: false,
                systemComponents: components, vendorUninstaller: uninstaller, needsAdministrator: needsAdministrator
            )
            apps.append(item)

            let isUnused = if let lastUsed = usage.lastUsed {
                lastUsed < cutoff
            } else {
                (usage.added ?? .distantFuture) < cutoff
            }
            if isUnused { unused.append(item) }
        }

        let claimed = Set(claimCount.keys)
        let orphans = findOrphans(
            in: libraryEntries.map(\.url).filter { !claimed.contains($0) },
            installedIDs: installedIDs,
            reporter: reporter
        )
        if Task.isCancelled { return [] }

        return [
            ScanCategory(
                id: "all",
                title: "Applications",
                description: "Everything installed in your Applications folders. Removing an app also removes the files it spread around.",
                symbol: Module.applications.symbol,
                metric: .count,
                items: apps.sorted { $0.totalSize > $1.totalSize }
            ),
            ScanCategory(
                id: "unused",
                title: "Unused Applications",
                description: "Apps you haven't opened in over three months.",
                symbol: "moon.zzz.fill",
                metric: .count,
                items: unused.sorted { $0.totalSize > $1.totalSize }
            ),
            ScanCategory(
                id: "leftovers",
                title: "App Leftovers",
                description: "Support files, caches and preferences that seem to belong to apps you've already deleted. Review before removing.",
                symbol: "puzzlepiece.extension.fill",
                items: orphans
            ),
        ]
    }

    // MARK: - System-wide parts

    /// A launch daemon or system-wide agent in /Library.
    private struct SystemLaunchEntry {
        let plist: URL
        let label: String
        let program: String?
        /// Apps macOS associates it with (shown in Login Items & Extensions).
        let associatedBundleIDs: [String]
    }

    private static func systemLaunchEntries() -> [SystemLaunchEntry] {
        ["/Library/LaunchDaemons", "/Library/LaunchAgents"]
            .flatMap { FileUtils.children(of: URL(fileURLWithPath: $0)) }
            .filter { $0.pathExtension == "plist" }
            .compactMap { plist in
                guard let dict = NSDictionary(contentsOf: plist) else { return nil }
                return SystemLaunchEntry(
                    plist: plist,
                    label: (dict["Label"] as? String) ?? plist.deletingPathExtension().lastPathComponent,
                    program: dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first,
                    associatedBundleIDs: (dict["AssociatedBundleIdentifiers"] as? [String]) ?? []
                )
            }
    }

    /// The app's system-wide launch items and the privileged helpers they run.
    private static func systemComponents(of app: AppRecord, in entries: [SystemLaunchEntry]) -> [URL] {
        let bundleID = app.bundleID.lowercased()
        var components: [URL] = []
        for entry in entries {
            let label = entry.label.lowercased()
            let belongsToApp = entry.associatedBundleIDs.contains { $0.lowercased() == bundleID }
                || (entry.program?.hasPrefix(app.url.path + "/") ?? false)
                || app.identifiers.contains { label == $0 || label.hasPrefix($0 + ".") }
            guard belongsToApp else { continue }
            components.append(entry.plist)
            if let program = entry.program, program.hasPrefix("/Library/PrivilegedHelperTools/"),
               FileManager.default.fileExists(atPath: program) {
                components.append(URL(fileURLWithPath: program))
            }
        }
        return components
    }

    /// The vendor's uninstaller, if the app ships one: referenced by its launch items, inside the
    /// app, or next to it (e.g. "Uninstall Foo.app").
    private static func vendorUninstaller(for app: AppRecord, components: [URL]) -> URL? {
        func isUninstaller(_ path: String) -> Bool {
            (path as NSString).lastPathComponent.lowercased().contains("uninstall") && path.hasSuffix(".app")
                && FileManager.default.fileExists(atPath: path)
        }
        let programs = components.compactMap { NSDictionary(contentsOf: $0)?["Program"] as? String }
        let fromComponents = programs.compactMap { program -> String? in
            var path = program
            while path.count > 1 {
                if isUninstaller(path) { return path }
                path = (path as NSString).deletingLastPathComponent
            }
            return nil
        }
        let nearby = (FileUtils.children(of: app.url.appendingPathComponent("Contents/Resources"))
            + FileUtils.children(of: app.url.deletingLastPathComponent()))
            .map(\.path)
            .filter { isUninstaller($0) && $0.lowercased().contains(app.name.lowercased()) || $0.hasPrefix(app.url.path + "/") && isUninstaller($0) }
        return (fromComponents + nearby).first.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Matching

    private static func belongs(_ entry: LibraryEntry, to app: AppRecord) -> Bool {
        let appName = app.name.lowercased()
        for name in entry.identifiers {
            for id in app.identifiers where name == id || name.hasPrefix(id + ".") || name.hasSuffix("." + id) {
                return true
            }
            if app.appGroups.contains(name) { return true }
            // Some apps use their display name, e.g. "Application Support/Steam".
            if appName.count >= 4, name == appName { return true }
        }
        // A launch agent whose program lives inside the app belongs to it, whatever it's called.
        if let program = entry.program, program.hasPrefix(app.url.path + "/") { return true }
        return false
    }

    private static func libraryEntry(for url: URL) -> LibraryEntry {
        let folder = url.deletingLastPathComponent().lastPathComponent
        let base = baseIdentifier(url)
        var names = [base]

        var parts = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "group" {
            parts.removeFirst()
            names.append(parts.joined(separator: "."))
        }
        if let first = parts.first, isTeamID(first), parts.count > 1 {
            names.append(parts.dropFirst().joined(separator: "."))
        }
        if pluginExtensions.contains(url.pathExtension.lowercased()),
           let pluginID = Bundle(url: url)?.bundleIdentifier {
            names.append(pluginID)
        }
        // Some containers are named by UUID; the owner is recorded in a metadata file inside.
        if folder == "Containers" || folder == "Group Containers", UUID(uuidString: url.lastPathComponent) != nil,
           let metadata = NSDictionary(contentsOf: url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")),
           let owner = metadata["MCMMetadataIdentifier"] as? String {
            names.append(owner)
        }

        var program: String?
        if folder == "LaunchAgents", url.pathExtension == "plist", let plist = NSDictionary(contentsOf: url) {
            if let label = plist["Label"] as? String { names.append(label) }
            program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        }
        return LibraryEntry(url: url, identifiers: names.map { $0.lowercased() }, program: program)
    }

    /// Bundle IDs of the helpers, extensions and login items shipped inside an app.
    private static func embeddedIdentifiers(in app: URL) -> [String] {
        let contents = app.appendingPathComponent("Contents")
        var ids: [String] = []
        for folder in embeddedFolders {
            for url in FileUtils.children(of: contents.appendingPathComponent(folder)) {
                if let id = Bundle(url: url)?.bundleIdentifier, url.pathExtension != "framework" {
                    ids.append(id)
                } else if folder == "Library/LaunchServices" {
                    // Privileged helper tools are bare executables named after their identifier.
                    ids.append(url.lastPathComponent)
                }
            }
        }
        return ids.map { $0.lowercased() }.filter(isDistinctiveIdentifier)
    }

    /// App groups from the app's code-signing entitlements, e.g. `group.com.foo` or `TEAMID.com.foo.shared`.
    private static func applicationGroups(of app: URL) -> [String] {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return [] }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        // Apple groups (group.com.apple.iWork, …) are shared with other Apple apps and system services.
        return groups.map { $0.lowercased() }.filter { !$0.contains("com.apple.") }
    }

    /// launchd labels to stop before the app goes: SMAppService agents bundled in
    /// Contents/Library/LaunchAgents and legacy login-item helpers (labelled by their bundle ID).
    private static func launchLabels(in app: URL) -> [String] {
        let library = app.appendingPathComponent("Contents/Library")
        let agents = FileUtils.children(of: library.appendingPathComponent("LaunchAgents"))
            .compactMap { NSDictionary(contentsOf: $0)?["Label"] as? String }
        let loginItems = FileUtils.children(of: library.appendingPathComponent("LoginItems"))
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
        return agents + loginItems
    }

    private static func isDistinctiveIdentifier(_ id: String) -> Bool {
        id.split(separator: ".").count >= 3 && !sharedIdentifierPrefixes.contains { id.hasPrefix($0) }
    }

    /// Values that appear in more than one of the sets.
    private static func duplicates(_ sets: [Set<String>]) -> Set<String> {
        var seen = Set<String>()
        var repeated = Set<String>()
        for set in sets {
            repeated.formUnion(set.intersection(seen))
            seen.formUnion(set)
        }
        return repeated
    }

    /// Apple team identifiers are ten uppercase letters and digits, e.g. `UBF8T346G9`.
    private static func isTeamID(_ string: String) -> Bool {
        string.count == 10 && string.allSatisfy { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }

    /// Strips the suffixes apps add to their identifier in different Library folders, plus the
    /// host UUID in `Preferences/ByHost` (`com.foo.App.<UUID>.plist` → `com.foo.App`).
    static func baseIdentifier(_ url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        if url.deletingLastPathComponent().lastPathComponent == "ByHost",
           let dot = name.lastIndex(of: "."),
           UUID(uuidString: String(name[name.index(after: dot)...])) != nil {
            name = String(name[..<dot])
        }
        return name
    }

    // MARK: - Orphans

    private static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "co", "app", "dev", "me", "info", "us", "uk", "de", "fr", "jp",
        "ru", "cn", "ch", "se", "no", "nl", "it", "es", "ca", "au", "tv", "cc", "ai",
    ]

    private static func findOrphans(in entries: [URL], installedIDs: Set<String>, reporter: ProgressReporter) -> [CleanItem] {
        var known: [String: Bool] = [:]

        func isKnown(_ identifier: String) -> Bool {
            var parts = identifier.split(separator: ".").map(String.init)
            while parts.count >= 2 {
                let candidate = parts.joined(separator: ".")
                if let cached = known[candidate] {
                    if cached { return true }
                } else {
                    let found = installedIDs.contains(candidate.lowercased())
                        || NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
                    known[candidate] = found
                    if found { return true }
                }
                parts.removeLast()
            }
            return false
        }

        var groups: [String: [URL]] = [:]
        for entry in entries where orphanFolders.contains(entry.deletingLastPathComponent().lastPathComponent) {
            if Task.isCancelled { return [] }
            let identifier = baseIdentifier(entry)
            let parts = identifier.lowercased().split(separator: ".")
            guard parts.count >= 3,
                  topLevelDomains.contains(String(parts[0])),
                  !identifier.lowercased().contains("apple"),
                  !isKnown(identifier)
            else { continue }
            groups[identifier, default: []].append(entry)
        }

        return groups.map { identifier, urls in
            reporter.report(urls[0].path)
            let files = urls.map { ExtraFile(url: $0, size: FileUtils.allocatedSize(of: $0, reporter: reporter)) }
            var seen = Set<String>()
            let locations = urls.map { $0.deletingLastPathComponent().lastPathComponent }.filter { seen.insert($0).inserted }
            return CleanItem(
                url: files[0].url,
                name: identifier,
                size: files[0].size,
                detail: locations.joined(separator: ", "),
                extras: Array(files.dropFirst()),
                removal: .trash,
                selectedByDefault: false
            )
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    private static func usageInfo(for url: URL) -> (lastUsed: Date?, added: Date?) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return (nil, nil) }
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        return (lastUsed, added)
    }
}
