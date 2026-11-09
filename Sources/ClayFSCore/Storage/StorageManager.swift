import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

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

        #if os(macOS)
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
        #elseif os(Linux)
        var finalBundleURL = bundleURL
        if !finalBundleURL.path.hasSuffix(".img") && !finalBundleURL.path.hasSuffix(".btrfs") {
            finalBundleURL = finalBundleURL.appendingPathExtension("img")
        }

        if FileManager.default.fileExists(atPath: finalBundleURL.path) {
            throw NSError(
                domain: "ClayFSStorage",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Image file already exists at \(finalBundleURL.path)"]
            )
        }

        // 1. Create sparse image file with truncate
        let truncRes = try ProcessRunner.run(
            executable: Self.toolPath("truncate", candidates: ["/usr/bin/truncate", "/bin/truncate"]),
            arguments: ["-s", size, finalBundleURL.path]
        )
        guard truncRes.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create sparse image file: \(truncRes.stderr)"]
            )
        }

        // 2. Format with Btrfs
        let mkfsRes = try ProcessRunner.run(
            executable: Self.toolPath("mkfs.btrfs", candidates: ["/sbin/mkfs.btrfs", "/usr/sbin/mkfs.btrfs", "/usr/bin/mkfs.btrfs"]),
            arguments: ["-f", "-K", finalBundleURL.path]
        )
        guard mkfsRes.isSuccess else {
            try? FileManager.default.removeItem(at: finalBundleURL)
            throw NSError(
                domain: "ClayFSStorage",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "mkfs.btrfs failed: \(mkfsRes.stderr)"]
            )
        }
        ClayFSPaths.ensureUserOwnership(at: finalBundleURL)
        #endif

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
        #if os(macOS)
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

        if let existingMount = findMountPoint(for: finalBundleURL) {
            return buildVolumeInfo(bundleURL: finalBundleURL, mountURL: existingMount)
        }

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

        guard let mountURL = parseMountPoint(fromPlistOutput: res.stdout) else {
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

        #elseif os(Linux)
        var finalBundleURL = bundleURL
        if !finalBundleURL.path.hasSuffix(".img") && !finalBundleURL.path.hasSuffix(".btrfs") && !FileManager.default.fileExists(atPath: finalBundleURL.path) {
            finalBundleURL = finalBundleURL.appendingPathExtension("img")
        }

        guard FileManager.default.fileExists(atPath: finalBundleURL.path) else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Image file not found: \(finalBundleURL.path)"]
            )
        }

        if let existingMount = findMountPoint(for: finalBundleURL) {
            return buildVolumeInfo(bundleURL: finalBundleURL, mountURL: existingMount)
        }

        let driveName = finalBundleURL.deletingPathExtension().lastPathComponent
        let userName: String
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"], !sudoUser.isEmpty {
            userName = sudoUser
        } else {
            userName = NSUserName()
        }
        let mountBase = URL(fileURLWithPath: "/media").appendingPathComponent(userName)
        let mountURL = mountBase.appendingPathComponent(driveName)

        do {
            try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        } catch {
            _ = try? ProcessRunner.run(
                executable: Self.toolPath("sudo", candidates: ["/usr/bin/sudo", "/bin/sudo"]),
                arguments: [Self.toolPath("mkdir", candidates: ["/bin/mkdir", "/usr/bin/mkdir"]), "-p", mountURL.path]
            )
        }
        ClayFSPaths.ensureUserOwnership(at: mountBase)
        ClayFSPaths.ensureUserOwnership(at: mountURL)

        let mountBin = Self.toolPath("mount", candidates: ["/bin/mount", "/usr/bin/mount", "/sbin/mount"])
        var mountRes = try ProcessRunner.run(
            executable: mountBin,
            arguments: ["-o", "loop,compress-force=zstd:3", finalBundleURL.path, mountURL.path]
        )
        #if os(Linux)
        if !mountRes.isSuccess && geteuid() != 0 {
            // Try fallback to sudo mount if unprivileged
            if let sudoRes = try? ProcessRunner.run(
                executable: Self.toolPath("sudo", candidates: ["/usr/bin/sudo", "/bin/sudo"]),
                arguments: [mountBin, "-o", "loop,compress-force=zstd:3", finalBundleURL.path, mountURL.path]
            ), sudoRes.isSuccess {
                mountRes = sudoRes
            }
        }
        #endif
        guard mountRes.isSuccess else {
            var errorMsg = mountRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            #if os(Linux)
            if geteuid() != 0 {
                errorMsg += "\nヒント: Linux での仮想ドライブのマウントには管理者権限が必要です。'sudo clayfs mount \(driveName)' を実行するか、sudoers で mount を許可してください。"
            }
            #endif
            throw NSError(
                domain: "ClayFSStorage",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Failed to mount Btrfs image: \(errorMsg)"]
            )
        }

        ClayFSPaths.ensureUserOwnership(at: mountURL)
        try initializeVolumeStructure(at: mountURL)
        ClayFSPaths.ensureUserOwnership(at: mountURL.appendingPathComponent(".clayfs"))
        let info = buildVolumeInfo(bundleURL: finalBundleURL, mountURL: mountURL)
        if register {
            try DriveRegistry.shared.registerDrive(info)
        }
        return info
        #endif
    }

    public func unmountDrive(
        mountURL: URL,
        force: Bool = false
    ) throws {
        #if os(macOS)
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
        #elseif os(Linux)
        var args = [mountURL.path]
        if force {
            args.insert("-l", at: 0)
        }
        let umountBin = Self.toolPath("umount", candidates: ["/bin/umount", "/usr/bin/umount", "/sbin/umount"])
        var res = try ProcessRunner.run(executable: umountBin, arguments: args)
        if !res.isSuccess && geteuid() != 0 {
            var sudoArgs = [umountBin]
            sudoArgs.append(contentsOf: args)
            if let sudoRes = try? ProcessRunner.run(
                executable: Self.toolPath("sudo", candidates: ["/usr/bin/sudo", "/bin/sudo"]),
                arguments: sudoArgs
            ), sudoRes.isSuccess {
                res = sudoRes
            }
        }
        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Failed to unmount \(mountURL.path): \(res.stderr)"]
            )
        }
        #endif
    }

    public func compactDrive(bundleURL: URL) throws {
        var finalBundleURL = bundleURL
        #if os(macOS)
        if !finalBundleURL.path.hasSuffix(".sparsebundle") && !FileManager.default.fileExists(atPath: finalBundleURL.path) {
            finalBundleURL = finalBundleURL.appendingPathExtension("sparsebundle")
        }

        let mountPoint = findMountPoint(for: finalBundleURL)
        var didUnmount = false

        if let mp = mountPoint {
            Darwin.sync()
            try unmountDrive(mountURL: mp)
            didUnmount = true
        }

        defer {
            if didUnmount {
                _ = try? mountDrive(bundleURL: finalBundleURL, showInFinder: true)
            }
        }

        let res = try ProcessRunner.hdiutil("compact", "-batteryallowed", finalBundleURL.path)
        guard res.isSuccess else {
            throw NSError(
                domain: "ClayFSStorage",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Failed to compact image: \(res.stderr)"]
            )
        }
        #elseif os(Linux)
        if !finalBundleURL.path.hasSuffix(".img") && !finalBundleURL.path.hasSuffix(".btrfs") && !FileManager.default.fileExists(atPath: finalBundleURL.path) {
            finalBundleURL = finalBundleURL.appendingPathExtension("img")
        }

        if let mp = findMountPoint(for: finalBundleURL) {
            Glibc.sync()
            // Btrfs defragmentation with zstd compression and fstrim to discard unused blocks
            _ = try? ProcessRunner.run(
                executable: Self.toolPath("btrfs", candidates: ["/bin/btrfs", "/usr/bin/btrfs", "/sbin/btrfs", "/usr/sbin/btrfs"]),
                arguments: ["filesystem", "defragment", "-r", "-czstd", mp.path]
            )
            _ = try? ProcessRunner.run(
                executable: Self.toolPath("fstrim", candidates: ["/sbin/fstrim", "/usr/sbin/fstrim", "/usr/bin/fstrim"]),
                arguments: ["-v", mp.path]
            )
        }
        #endif
    }

    public func getAllMountPoints() -> [String: URL] {
        #if os(macOS)
        do {
            let res = try ProcessRunner.hdiutil("info", "-plist")
            guard res.isSuccess, let data = res.stdout.data(using: .utf8) else { return [:] }
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else {
                return [:]
            }

            var map: [String: URL] = [:]
            for img in images {
                guard let imgPath = img["image-path"] as? String else { continue }
                let standardImgPath = URL(fileURLWithPath: imgPath).resolvingSymlinksInPath().path
                if let entities = img["system-entities"] as? [[String: Any]] {
                    for entity in entities {
                        if let mp = entity["mount-point"] as? String {
                            map[standardImgPath] = URL(fileURLWithPath: mp)
                            break
                        }
                    }
                }
            }
            return map
        } catch {
            return [:]
        }
        #elseif os(Linux)
        // Parse /proc/mounts safely using getline (avoids Foundation 4KB truncation on procfs)
        guard let fp = fopen("/proc/mounts", "r") else {
            return [:]
        }
        defer { fclose(fp) }

        var lines: [String] = []
        var lineBuffer: UnsafeMutablePointer<CChar>? = nil
        var lineCap: Int = 0
        while getline(&lineBuffer, &lineCap, fp) > 0 {
            if let linePtr = lineBuffer {
                lines.append(String(cString: linePtr).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if let linePtr = lineBuffer {
            free(linePtr)
        }

        // Loop device to backing file map
        var loopMap: [String: String] = [:]
        if let loopDirs = try? FileManager.default.contentsOfDirectory(atPath: "/sys/block") {
            for loopName in loopDirs where loopName.hasPrefix("loop") {
                let backingPath = "/sys/block/\(loopName)/loop/backing_file"
                if let realFile = try? String(contentsOfFile: backingPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines) {
                    let standardFile = URL(fileURLWithPath: realFile).resolvingSymlinksInPath().path
                    loopMap["/dev/\(loopName)"] = standardFile
                }
            }
        }

        var map: [String: URL] = [:]
        for line in lines {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            let dev = Self.unescapeMountField(String(parts[0]))
            // /proc/mounts は、空白 ('\040') や改行、タブを 8 進数でエスケープして書く。
            // 空白を含むマウント先 (試験で扱う名前も含む) は、解かないと登録済みのパスと一致しない
            let mountPath = Self.unescapeMountField(String(parts[1]))
            if let backingFile = loopMap[dev] {
                map[backingFile] = URL(fileURLWithPath: mountPath)
            }
        }
        return map
        #endif
    }

    /// ツールの場所を決める。/bin と /usr/bin が分かれているディストリビューション (Arch、Alpine など)
    /// もあるので、決め打ちにせず、あるものを探す。
    static func toolPath(_ name: String, candidates: [String]) -> String {
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return candidates[0]
    }

    /// /proc/mounts のフィールドの 8 進数エスケープ (\040 など) を解く。
    static func unescapeMountField(_ field: String) -> String {
        guard field.contains("\\") else { return field }
        var out = ""
        let chars = Array(field)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 3 < chars.count,
               let v = Int(String(chars[(i + 1)...(i + 3)]), radix: 8), v > 0, v < 0x80 {
                out.append(Character(UnicodeScalar(UInt8(v))))
                i += 4
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    public func findMountPoint(for bundleURL: URL) -> URL? {
        let standardBundlePath = bundleURL.resolvingSymlinksInPath().path
        return getAllMountPoints()[standardBundlePath]
    }

    #if os(macOS)
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
    #endif

    private func initializeVolumeStructure(at mountURL: URL) throws {
        let metadataURL = mountURL.appendingPathComponent(".clayfs")
        let snapshotsURL = metadataURL.appendingPathComponent("snapshots")
        let noIndexURL = metadataURL.appendingPathComponent(".metadata_never_index")

        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: noIndexURL.path) {
            _ = FileManager.default.createFile(atPath: noIndexURL.path, contents: nil)
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

        let existing = DriveRegistry.shared.loadDrives().first(where: { $0.bundleURL.standardizedFileURL == bundleURL.standardizedFileURL })

        return VolumeInfo(
            name: name,
            bundleURL: bundleURL,
            mountURL: mountURL,
            isMounted: mountURL != nil,
            sizeLimit: existing?.sizeLimit ?? "50g",
            freeBytes: freeBytes,
            totalBytes: totalBytes,
            autoSnapshot: existing?.autoSnapshot ?? true,
            autoMount: existing?.autoMount ?? true,
            retentionPolicy: existing?.retentionPolicy ?? .default
        )
    }
}
