import Foundation
import SQLite3

/// Apple's built-in malware definitions (XProtect), read straight from the system. Apple
/// updates them in the background, so Squeaky always scans with the current set without
/// shipping or downloading any signatures itself. Everything here is world-readable.
struct XProtectCatalog: Sendable {
    let resources: URL
    let version: Int
    let updated: Date?

    /// Sequoia and later keep a copy under /var/protected; older systems only have the bundle.
    private static let candidates = [
        "/var/protected/xprotect/XProtect.bundle/Contents/Resources",
        "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources",
    ]

    /// The newest readable copy, or nil if XProtect isn't available.
    static func load() -> XProtectCatalog? {
        candidates.compactMap { path -> XProtectCatalog? in
            let resources = URL(fileURLWithPath: path)
            let meta = resources.appendingPathComponent("XProtect.meta.plist")
            guard let plist = NSDictionary(contentsOf: meta),
                  let version = (plist["Version"] as? NSNumber)?.intValue,
                  FileManager.default.isReadableFile(atPath: resources.appendingPathComponent("XProtect.yara").path)
            else { return nil }
            let updated = (try? meta.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return XProtectCatalog(resources: resources, version: version, updated: updated)
        }
        .max { $0.version < $1.version }
    }

    /// YARA rule files: binaries (`XProtect.yara`) and scripts (`XPScripts.yr`).
    var yaraSources: [(name: String, text: String)] {
        ["XProtect.yara", "XPScripts.yr"].compactMap { name in
            guard let text = try? String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return (name, text)
        }
    }

    /// Rule name → its `description` meta (e.g. "MACOS.cbb1424", "OSX.Bundlore.D").
    func ruleDescriptions(in sources: [(name: String, text: String)]) -> [String: String] {
        var descriptions: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"rule\s+(\w+)[^{]*\{\s*meta:\s*description\s*=\s*"([^"]+)""#)
        for source in sources {
            let text = source.text as NSString
            for match in pattern.matches(in: source.text, range: NSRange(location: 0, length: text.length)) {
                descriptions[text.substring(with: match.range(at: 1))] = text.substring(with: match.range(at: 2))
            }
        }
        return descriptions
    }

    /// Gatekeeper's blocklist: code-directory hashes and developer team IDs Apple has revoked.
    func gatekeeperBlocklist() -> (hashes: Set<Data>, teams: Set<String>) {
        var database: OpaquePointer?
        let path = resources.appendingPathComponent("gk.db").path
        // SQLite can allocate a handle even when opening fails.
        defer { if let database { sqlite3_close(database) } }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return ([], []) }

        var hashes = Set<Data>()
        var teams = Set<String>()
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, "SELECT hash FROM blocked_hashes", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let bytes = sqlite3_column_blob(statement, 0) {
                    hashes.insert(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
                }
            }
        }
        sqlite3_finalize(statement)
        statement = nil
        if sqlite3_prepare_v2(database, "SELECT team_id FROM blocked_teams", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) { teams.insert(String(cString: text)) }
            }
        }
        sqlite3_finalize(statement)
        return (hashes, teams)
    }

    /// Safari extensions Apple blocks, as (bundle identifier, developer team ID).
    var blockedSafariExtensions: [(bundleID: String, team: String)] {
        guard let meta = NSDictionary(contentsOf: resources.appendingPathComponent("XProtect.meta.plist")),
              let list = (meta["ExtensionBlacklist"] as? NSDictionary)?["Extensions"] as? [NSDictionary]
        else { return [] }
        return list.compactMap { entry in
            guard let bundleID = entry["CFBundleIdentifier"] as? String,
                  let team = entry["Developer Identifier"] as? String
            else { return nil }
            return (bundleID, team)
        }
    }
}
