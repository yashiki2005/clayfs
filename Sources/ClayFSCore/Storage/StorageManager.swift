import Foundation

public final class StorageManager: Sendable {
    public static let shared = StorageManager()

    public init() {}

    public func createDrive(
        name: String,
        size: String = "50g",
        bundleURL: URL,
        register: Bool = true
    ) throws -> VolumeInfo {
        let parentDir = bundleURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var finalBundleURL = bundleURL
        if !finalBundleURL.path.hasSuffix(".sparsebundle") {
            finalBundleURL = finalBundleURL.appendingPathExtension("sparsebundle")
        }

        if FileManager.default.fileExists(atPath: finalBundleURL.path) {
            throw NSError(
                domain: "ClayFSStorage",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Sparsebundle already exists at \(finalBundleURL.path)"]
            )
        }

        // hdiutil create -size 50g -type SPARSEBUNDLE -fs APFS -volname <name> <bundlePath>
        let res = try ProcessRunner.hdiutil(
            "create",
            "-size", size,
            "-type", "SPARSEBUNDLE",
            "-fs", "APFS",
            "-volname", name,
            finalBundleURL.path
        )

        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create sparsebundle: \(res.stderr)"]
            )
        }

        let drive = VolumeInfo(
            name: name,
            bundleURL: finalBundleURL,
            mountURL: nil,
            isMounted: false,
            sizeLimit: size
        )

        if register {
            try DriveRegistry.shared.registerDrive(drive)
        }
        return drive
    }

    public func mountDrive(
        bundleURL: URL,
        showInFinder: Bool = true,
        register: Bool = true
    ) throws -> VolumeInfo {
        var finalBundleURL = bundleURL
        if !finalBundleURL.path.hasSuffix(".sparsebundle") && !FileManager.default.fileExists(atPath: finalBundleURL.path) {
            finalBundleURL = finalBundleURL.appendingPathExtension("sparsebundle")
        }

        guard FileManager.default.fileExists(atPath: finalBundleURL.path) else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Sparsebundle not found: \(finalBundleURL.path)"]
            )
        }

        // Check if already mounted
        if let existingMount = findMountPoint(for: finalBundleURL) {
            return buildVolumeInfo(bundleURL: finalBundleURL, mountURL: existingMount)
        }

        // hdiutil attach [-nobrowse] -owners on <bundlePath> -plist
        var args = ["attach", "-owners", "on", finalBundleURL.path, "-plist"]
        if !showInFinder {
            args.insert("-nobrowse", at: 1)
        }

        let res = try ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: args)
        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Failed to attach image: \(res.stderr)"]
            )
        }

        // Parse plist to get mount point
        guard let mountURL = parseMountPoint(fromPlistOutput: res.stdout) else {
            // Fallback: search hdiutil info
            if let found = findMountPoint(for: finalBundleURL) {
                try initializeVolumeStructure(at: found)
                return buildVolumeInfo(bundleURL: finalBundleURL, mountURL: found)
            }
            throw NSError(
                domain: "ClayFSStorage",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Attached image, but could not determine mount point"]
            )
        }

        try initializeVolumeStructure(at: mountURL)
        let info = buildVolumeInfo(bundleURL: finalBundleURL, mountURL: mountURL)
        if register {
            try DriveRegistry.shared.registerDrive(info)
        }
        return info
    }

    public func unmountDrive(
        mountURL: URL,
        force: Bool = false
    ) throws {
        var args = ["detach", mountURL.path]
        if force {
            args.append("-force")
        }
        let res = try ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: args)
        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Failed to unmount \(mountURL.path): \(res.stderr)"]
            )
        }
    }

    public func compactDrive(bundleURL: URL) throws {
        let res = try ProcessRunner.hdiutil("compact", bundleURL.path)
        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Failed to compact image: \(res.stderr)"]
            )
        }
    }

    public func findMountPoint(for bundleURL: URL) -> URL? {
        do {
            let res = try ProcessRunner.hdiutil("info", "-plist")
            guard res.isSuccess, let data = res.stdout.data(using: .utf8) else { return nil }
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else {
                return nil
            }

            let standardBundlePath = bundleURL.resolvingSymlinksInPath().path
            for img in images {
                if let imgPath = img["image-path"] as? String {
                    let standardImgPath = URL(fileURLWithPath: imgPath).resolvingSymlinksInPath().path
                    if standardImgPath == standardBundlePath {
                        if let entities = img["system-entities"] as? [[String: Any]] {
                            for entity in entities {
                                if let mp = entity["mount-point"] as? String {
                                    return URL(fileURLWithPath: mp)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func parseMountPoint(fromPlistOutput output: String) -> URL? {
        guard let data = output.data(using: .utf8) else { return nil }
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]] else {
                return nil
            }
            for entity in entities {
                if let mp = entity["mount-point"] as? String {
                    return URL(fileURLWithPath: mp)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func initializeVolumeStructure(at mountURL: URL) throws {
        let workspaceURL = mountURL.appendingPathComponent("Workspace")
        let metadataURL = mountURL.appendingPathComponent(".clayfs")
        let snapshotsURL = metadataURL.appendingPathComponent("snapshots")
        let noIndexURL = metadataURL.appendingPathComponent(".metadata_never_index")

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: noIndexURL.path) {
            FileManager.default.createFile(atPath: noIndexURL.path, contents: nil)
        }
    }

    private func buildVolumeInfo(bundleURL: URL, mountURL: URL?) -> VolumeInfo {
        let name = bundleURL.deletingPathExtension().lastPathComponent
        var freeBytes: Int64 = 0
        var totalBytes: Int64 = 0

        if let mountURL = mountURL {
            do {
                let values = try mountURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
                freeBytes = Int64(values.volumeAvailableCapacity ?? 0)
                totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            } catch {}
        }

        return VolumeInfo(
            name: name,
            bundleURL: bundleURL,
            mountURL: mountURL,
            isMounted: mountURL != nil,
            freeBytes: freeBytes,
            totalBytes: totalBytes
        )
    }
}
