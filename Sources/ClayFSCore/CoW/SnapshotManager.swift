import Foundation
import Darwin

public final class SnapshotManager: Sendable {
    public static let shared = SnapshotManager()

    public static let ignoredRootNames: Set<String> = [
        ".clayfs",
        ".fseventsd",
        ".Trashes",
        ".Spotlight-V100",
        ".DocumentRevisions-V100",
        ".TemporaryItems",
        ".VolumeIcon.icns",
        ".com.apple.timemachine.donotpresent"
    ]

    public init() {}

    public func createSnapshot(
        volumeMountURL: URL,
        message: String = "Manual snapshot",
        author: String = NSUserName()
    ) throws -> Snapshot {
        let metadataURL = volumeMountURL.appendingPathComponent(".clayfs")
        let snapshotsURL = metadataURL.appendingPathComponent("snapshots")
        let dbURL = metadataURL.appendingPathComponent("timeline.sqlite3")

        guard FileManager.default.fileExists(atPath: volumeMountURL.path) else {
            throw NSError(
                domain: "ClayFSSnapshot",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Volume mount path does not exist at \(volumeMountURL.path)"]
            )
        }

        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone.current
        let baseID = formatter.string(from: Date())
        var id = baseID
        var snapshotDestURL = snapshotsURL.appendingPathComponent(id)
        var counter = 1
        while FileManager.default.fileExists(atPath: snapshotDestURL.path) {
            id = "\(baseID)_\(counter)"
            snapshotDestURL = snapshotsURL.appendingPathComponent(id)
            counter += 1
        }

        try FileManager.default.createDirectory(at: snapshotDestURL, withIntermediateDirectories: true)

        // Clone all user items at the volume root into the snapshot directory
        let items = try FileManager.default.contentsOfDirectory(at: volumeMountURL, includingPropertiesForKeys: nil, options: [])
        for item in items {
            let name = item.lastPathComponent
            if Self.ignoredRootNames.contains(name) {
                continue
            }
            let destItem = snapshotDestURL.appendingPathComponent(name)
            let rc = clonefile(item.path, destItem.path, 0)
            guard rc == 0 else {
                let err = errno
                throw NSError(
                    domain: "ClayFSSnapshot",
                    code: 21,
                    userInfo: [NSLocalizedDescriptionKey: "APFS clonefile failed for \(name) with errno \(err): \(String(cString: strerror(err)))"]
                )
            }
        }

        // Count files and compute logical size (quick limit so large directories never block)
        let (fileCount, totalBytes, isComplete) = calculateMetrics(for: snapshotDestURL, maxItems: 500)

        let snapshot = Snapshot(
            id: id,
            timestamp: Date(),
            message: message,
            author: author,
            fileCount: fileCount,
            totalBytes: totalBytes
        )

        let db = try TimelineDB(fileURL: dbURL)
        try db.insertSnapshot(snapshot)

        // If directory has more than 500 items, finish computing full metrics in background queue
        if !isComplete {
            let snapID = id
            let targetURL = snapshotDestURL
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                let (fullCount, fullBytes) = self.calculateFullMetrics(for: targetURL)
                if let db = try? TimelineDB(fileURL: dbURL) {
                    try? db.updateMetrics(id: snapID, fileCount: fullCount, totalBytes: fullBytes)
                }
            }
        }

        return snapshot
    }

    public func listSnapshots(volumeMountURL: URL, limit: Int = 100) throws -> [Snapshot] {
        let dbURL = volumeMountURL.appendingPathComponent(".clayfs/timeline.sqlite3")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return []
        }
        let db = try TimelineDB(fileURL: dbURL)
        return db.getSnapshots(limit: limit)
    }

    public func restore(
        volumeMountURL: URL,
        snapshotID: String,
        subpath: String? = nil
    ) throws {
        let snapshotSourceURL = volumeMountURL
            .appendingPathComponent(".clayfs/snapshots")
            .appendingPathComponent(snapshotID)

        guard FileManager.default.fileExists(atPath: snapshotSourceURL.path) else {
            throw NSError(
                domain: "ClayFSSnapshot",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "Snapshot \(snapshotID) does not exist at \(snapshotSourceURL.path)"]
            )
        }

        // Take a safety snapshot first if volume has content
        _ = try? createSnapshot(volumeMountURL: volumeMountURL, message: "Safety snapshot before restoring to \(snapshotID)")

        if let subpath = subpath, !subpath.isEmpty {
            let sourceItem = snapshotSourceURL.appendingPathComponent(subpath)
            let destItem = volumeMountURL.appendingPathComponent(subpath)

            guard FileManager.default.fileExists(atPath: sourceItem.path) else {
                throw NSError(
                    domain: "ClayFSSnapshot",
                    code: 23,
                    userInfo: [NSLocalizedDescriptionKey: "Subpath \(subpath) not found in snapshot \(snapshotID)"]
                )
            }

            if FileManager.default.fileExists(atPath: destItem.path) {
                try FileManager.default.removeItem(at: destItem)
            }
            try FileManager.default.createDirectory(at: destItem.deletingLastPathComponent(), withIntermediateDirectories: true)

            let rc = clonefile(sourceItem.path, destItem.path, 0)
            guard rc == 0 else {
                let err = errno
                throw NSError(
                    domain: "ClayFSSnapshot",
                    code: 24,
                    userInfo: [NSLocalizedDescriptionKey: "APFS clonefile restore failed: \(String(cString: strerror(err)))"]
                )
            }
        } else {
            // Full restore:
            let tempBackup = volumeMountURL.appendingPathComponent(".clayfs/temp_restore_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempBackup, withIntermediateDirectories: true)

            // Move current top-level user items into tempBackup
            let currentItems = (try? FileManager.default.contentsOfDirectory(at: volumeMountURL, includingPropertiesForKeys: nil, options: [])) ?? []
            for item in currentItems {
                let name = item.lastPathComponent
                if Self.ignoredRootNames.contains(name) {
                    continue
                }
                let targetURL = tempBackup.appendingPathComponent(name)
                try? FileManager.default.moveItem(at: item, to: targetURL)
            }

            // Clone all items from snapshotSourceURL to volumeMountURL
            let snapItems = (try? FileManager.default.contentsOfDirectory(at: snapshotSourceURL, includingPropertiesForKeys: nil, options: [])) ?? []
            for item in snapItems {
                let destItem = volumeMountURL.appendingPathComponent(item.lastPathComponent)
                let rc = clonefile(item.path, destItem.path, 0)
                if rc != 0 {
                    let err = errno
                    throw NSError(
                        domain: "ClayFSSnapshot",
                        code: 25,
                        userInfo: [NSLocalizedDescriptionKey: "APFS clonefile restore failed for \(item.lastPathComponent): \(String(cString: strerror(err)))"]
                    )
                }
            }

            // Clean up old temporary directory in background so restore finishes instantly
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.removeItem(at: tempBackup)
            }
        }
    }

    public func diff(
        volumeMountURL: URL,
        snapshotID: String? = nil
    ) throws -> [FileDiff] {
        let targetSnapshotID: String

        if let snapshotID = snapshotID {
            targetSnapshotID = snapshotID
        } else {
            guard let latest = try listSnapshots(volumeMountURL: volumeMountURL, limit: 1).first else {
                return []
            }
            targetSnapshotID = latest.id
        }

        let snapshotURL = volumeMountURL
            .appendingPathComponent(".clayfs/snapshots")
            .appendingPathComponent(targetSnapshotID)

        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return []
        }

        return computeDiff(between: snapshotURL, and: volumeMountURL)
    }

    private func calculateMetrics(for directoryURL: URL, maxItems: Int = 500) -> (fileCount: Int, totalBytes: Int64, isComplete: Bool) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, true)
        }

        var count = 0
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            count += 1
            totalBytes += Int64(values.fileSize ?? 0)
            if count >= maxItems {
                return (count, totalBytes, false)
            }
        }
        return (count, totalBytes, true)
    }

    private func calculateFullMetrics(for directoryURL: URL) -> (fileCount: Int, totalBytes: Int64) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var count = 0
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            count += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return (count, totalBytes)
    }

    private func computeDiff(between snapshotURL: URL, and workspaceURL: URL) -> [FileDiff] {
        let snapFiles = collectFiles(in: snapshotURL)
        let workFiles = collectFiles(in: workspaceURL)

        var diffs: [FileDiff] = []

        // Check for added and modified files
        for (relPath, workAttrs) in workFiles {
            if let snapAttrs = snapFiles[relPath] {
                if workAttrs.size != snapAttrs.size || workAttrs.mtime != snapAttrs.mtime {
                    diffs.append(FileDiff(path: relPath, change: .modified, size: workAttrs.size))
                }
            } else {
                diffs.append(FileDiff(path: relPath, change: .added, size: workAttrs.size))
            }
        }

        // Check for deleted files
        for (relPath, snapAttrs) in snapFiles {
            if workFiles[relPath] == nil {
                diffs.append(FileDiff(path: relPath, change: .deleted, size: snapAttrs.size))
            }
        }

        return diffs.sorted(by: { $0.path < $1.path })
    }

    private struct FileMeta {
        let size: Int64
        let mtime: Date
    }

    private func collectFiles(in rootURL: URL) -> [String: FileMeta] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let rootPath = rootURL.path
        var map: [String: FileMeta] = [:]

        for case let fileURL as URL in enumerator {
            let rel = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            let rootComp = rel.split(separator: "/").first.map(String.init) ?? rel
            if Self.ignoredRootNames.contains(rootComp) {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            map[rel] = FileMeta(
                size: Int64(values.fileSize ?? 0),
                mtime: values.contentModificationDate ?? Date()
            )
        }
        return map
    }
}
