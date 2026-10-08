import Foundation

/// Looks through the user's own folders for duplicates, large files and stale downloads.
/// Everything found here is user data, so it always goes to the Trash.
enum ClutterScanner {
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024
    static let duplicateMinimumSize: Int64 = 1024 * 1024
    static let staleAfter: TimeInterval = 90 * 24 * 60 * 60

    private struct FileRecord {
        let url: URL
        let size: Int64
        let modified: Date
    }

    static func scan(_ reporter: ProgressReporter) async -> [ScanCategory] {
        let home = FileUtils.home
        let downloads = home.appendingPathComponent("Downloads")
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0) }

        var files: [FileRecord] = []
        for root in roots {
            if Task.isCancelled { return [] }
            files += collect(root, reporter: reporter)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        // Large files
        let large = files
            .filter { $0.size >= largeFileThreshold }
            .sorted { $0.size > $1.size }
            .map {
                CleanItem(
                    url: $0.url,
                    name: $0.url.lastPathComponent,
                    size: $0.size,
                    detail: "\($0.url.deletingLastPathComponent().abbreviatedPath) · modified \(dateFormatter.string(from: $0.modified))",
                    removal: .trash,
                    selectedByDefault: false
                )
            }

        // Old downloads (top level of ~/Downloads only, like Finder shows them)
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let brokenExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]
        let oldDownloads: [CleanItem] = FileUtils.children(of: downloads).compactMap { url in
            guard !brokenExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
            else { return nil }
            let lastTouched = max(values.contentModificationDate ?? .distantPast, values.addedToDirectoryDate ?? .distantPast)
            guard lastTouched < cutoff else { return nil }
            reporter.report(url.path)
            return CleanItem(
                url: url,
                name: url.lastPathComponent,
                size: FileUtils.allocatedSize(of: url, reporter: reporter),
                detail: "Added \(dateFormatter.string(from: lastTouched))",
                removal: .trash,
                selectedByDefault: false
            )
        }
        .sorted { $0.size > $1.size }

        let duplicates = findDuplicates(in: files, downloads: downloads, reporter: reporter)
        if Task.isCancelled { return [] }

        return [
            ScanCategory(
                id: SweepModel.duplicatesID,
                title: "Duplicates",
                description: "Identical copies of the same file. We keep the oldest copy and pre-select the extras in Downloads.",
                symbol: "doc.on.doc.fill",
                metric: .count,
                items: duplicates
            ),
            ScanCategory(
                id: "large",
                title: "Large Files",
                description: "Files over \(largeFileThreshold.formattedBytes) in your personal folders. Decide what you still need.",
                symbol: "externaldrive.fill",
                items: large
            ),
            ScanCategory(
                id: "old-downloads",
                title: "Old Downloads",
                description: "Things in your Downloads folder you haven't touched in over three months.",
                symbol: "arrow.down.circle.fill",
                items: oldDownloads
            ),
        ]
    }

    private static func collect(_ root: URL, reporter: ProgressReporter) -> [FileRecord] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var records: [FileRecord] = []
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            count += 1
            if count % 200 == 0 {
                if Task.isCancelled { break }
                reporter.report(url.path)
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true,
                  let size = v.fileSize
            else { continue }
            // Skip iCloud placeholders: reading them would trigger a download.
            if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus != .current { continue }
            records.append(FileRecord(url: url, size: Int64(size), modified: v.contentModificationDate ?? .distantPast))
        }
        return records
    }

    /// Size → first-64KB hash → full hash, so we only fully read files that are very likely identical.
    private static func findDuplicates(in files: [FileRecord], downloads: URL, reporter: ProgressReporter) -> [CleanItem] {
        let candidates = Dictionary(grouping: files.filter { $0.size >= duplicateMinimumSize }, by: \.size)
            .values
            .filter { $0.count > 1 }

        var groups: [[FileRecord]] = []
        for sameSize in candidates {
            if Task.isCancelled { return [] }
            let byPrefix = Dictionary(grouping: sameSize) {
                reporter.report($0.url.path)
                return FileUtils.sha256(of: $0.url, limit: 64 * 1024) ?? UUID().uuidString
            }
            for samePrefix in byPrefix.values where samePrefix.count > 1 {
                let byContent = Dictionary(grouping: samePrefix) {
                    reporter.report($0.url.path)
                    return FileUtils.sha256(of: $0.url) ?? UUID().uuidString
                }
                groups += byContent.values.filter { $0.count > 1 }
            }
        }

        let downloadsPath = downloads.path + "/"
        return groups
            .sorted { $0[0].size > $1[0].size }
            .flatMap { group -> [CleanItem] in
                let sorted = group.sorted { $0.modified < $1.modified }
                let original = sorted[0]
                return sorted.dropFirst().map { copy in
                    CleanItem(
                        url: copy.url,
                        name: copy.url.lastPathComponent,
                        size: copy.size,
                        detail: "Copy of \(original.url.abbreviatedPath)",
                        removal: .trash,
                        selectedByDefault: copy.url.path.hasPrefix(downloadsPath)
                    )
                }
            }
    }
}
