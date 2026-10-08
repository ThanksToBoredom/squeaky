import Foundation

/// Finds regenerable junk: caches, logs, Xcode leftovers, the Trash, Mail
/// attachments, interrupted downloads and package-manager caches.
enum JunkScanner {
    static func scan(_ reporter: ProgressReporter) async -> [ScanCategory] {
        let home = FileUtils.home
        let library = FileUtils.library
        let ownBundleID = Bundle.main.bundleIdentifier ?? "no.neobits.Squeaky"

        func sized(_ urls: [URL], removal: RemovalMethod) -> [CleanItem] {
            urls.compactMap { url -> CleanItem? in
                if Task.isCancelled { return nil }
                reporter.report(url.path)
                let size = FileUtils.allocatedSize(of: url, reporter: reporter)
                guard size > 0 else { return nil }
                return CleanItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: size,
                    detail: url.deletingLastPathComponent().abbreviatedPath,
                    removal: removal
                )
            }
            .sorted { $0.size > $1.size }
        }

        let caches = FileUtils.children(of: library.appendingPathComponent("Caches")).filter {
            let name = $0.lastPathComponent
            // Apple's own caches are mostly SIP/TCC-protected and some are expensive to rebuild.
            return !name.hasPrefix("com.apple.") && name != ownBundleID && name != "CloudKit"
        }

        let xcode = [
            "Developer/Xcode/DerivedData",
            "Developer/Xcode/iOS DeviceSupport",
            "Developer/Xcode/watchOS DeviceSupport",
            "Developer/CoreSimulator/Caches",
        ].flatMap { FileUtils.children(of: library.appendingPathComponent($0)) }

        let brokenExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]
        let brokenDownloads = FileUtils.children(of: home.appendingPathComponent("Downloads"))
            .filter { brokenExtensions.contains($0.pathExtension.lowercased()) }

        let devCaches = [".npm/_cacache", ".gradle/caches", ".pnpm-store", ".cocoapods/repos/trunk"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let categories = [
            ScanCategory(
                id: "caches",
                title: "User Cache Files",
                description: "Temporary files apps keep to speed things up. They're rebuilt automatically when needed.",
                symbol: "archivebox.fill",
                items: sized(caches, removal: .delete)
            ),
            ScanCategory(
                id: "logs",
                title: "Log Files",
                description: "Diagnostic logs and crash reports apps have written over time.",
                symbol: "doc.text.fill",
                items: sized(FileUtils.children(of: library.appendingPathComponent("Logs")), removal: .delete)
            ),
            ScanCategory(
                id: "xcode",
                title: "Xcode Junk",
                description: "Derived data, old device support files and simulator caches left behind by Xcode.",
                symbol: "hammer.fill",
                items: sized(xcode, removal: .delete)
            ),
            ScanCategory(
                id: "trash",
                title: "Trash Bins",
                description: "Files you've already thrown away still take up space until the Trash is emptied.",
                symbol: "trash.fill",
                items: sized(FileUtils.children(of: home.appendingPathComponent(".Trash"), includeHidden: true), removal: .delete)
            ),
            ScanCategory(
                id: "mail",
                title: "Mail Attachments",
                description: "Attachments Mail has downloaded. You can always get them again from your mailbox.",
                symbol: "envelope.fill",
                items: sized(
                    FileUtils.children(of: library.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads")),
                    removal: .delete
                )
            ),
            ScanCategory(
                id: "broken-downloads",
                title: "Broken Downloads",
                description: "Downloads that were interrupted and can't be resumed.",
                symbol: "arrow.down.circle.fill",
                items: sized(brokenDownloads, removal: .trash)
            ),
            ScanCategory(
                id: "dev-caches",
                title: "Developer Caches",
                description: "Package caches from npm, Gradle, pnpm and CocoaPods. They're re-downloaded on demand.",
                symbol: "shippingbox.fill",
                items: sized(devCaches, removal: .delete)
            ),
        ]

        return categories.sorted { $0.totalSize > $1.totalSize }
    }
}
