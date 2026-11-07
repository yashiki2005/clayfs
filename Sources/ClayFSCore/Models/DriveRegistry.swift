import Foundation

public final class DriveRegistry: @unchecked Sendable {
    public static let shared = DriveRegistry()

    private let configURL: URL
    private let lock = NSLock()

    public init(configURL: URL? = nil) {
        if let configURL = configURL {
            self.configURL = configURL
        } else {
            let home = ClayFSPaths.effectiveHomeDirectory
            self.configURL = home.appendingPathComponent(".config/clayfs/drives.json")
        }
    }

    private func withFileLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }

        let lockURL = configURL.deletingLastPathComponent().appendingPathComponent("drives.lock")
        try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 {
            flock(fd, LOCK_EX)
            defer {
                flock(fd, LOCK_UN)
                close(fd)
            }
            return try work()
        }
        return try work()
    }

    private func loadDrivesInternal(cleanMissing: Bool) throws -> [VolumeInfo] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return []
        }
        let data = try Data(contentsOf: configURL)
        guard !data.isEmpty else { return [] }
        do {
            var drives = try JSONDecoder().decode([VolumeInfo].self, from: data)
            if cleanMissing {
                let existing = drives.filter { FileManager.default.fileExists(atPath: $0.bundleURL.path) }
                if existing.count != drives.count {
                    drives = existing
                    try saveDrivesInternal(existing)
                }
            }
            return drives
        } catch {
            let backupURL = configURL.appendingPathExtension("corrupted.\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: configURL, to: backupURL)
            throw NSError(
                domain: "ClayFSDriveRegistry",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "drives.json is corrupted (backed up to \(backupURL.lastPathComponent)): \(error.localizedDescription)"]
            )
        }
    }

    private func saveDrivesInternal(_ drives: [VolumeInfo]) throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(drives)
        try data.write(to: configURL, options: .atomic)
    }

    public func loadDrives(cleanMissing: Bool = false) -> [VolumeInfo] {
        withFileLock {
            (try? loadDrivesInternal(cleanMissing: cleanMissing)) ?? []
        }
    }

    public func saveDrives(_ drives: [VolumeInfo]) throws {
        try withFileLock {
            try saveDrivesInternal(drives)
        }
    }

    public func registerDrive(_ drive: VolumeInfo) throws {
        try withFileLock {
            var drives = try loadDrivesInternal(cleanMissing: false)
            if let idx = drives.firstIndex(where: { $0.name == drive.name }) {
                drives[idx] = drive
            } else {
                drives.append(drive)
            }
            try saveDrivesInternal(drives)
        }
    }

    public func unregisterDrive(named name: String) throws {
        try withFileLock {
            var drives = try loadDrivesInternal(cleanMissing: false)
            drives.removeAll(where: { $0.name == name })
            try saveDrivesInternal(drives)
        }
    }

    public func findDrive(named name: String) -> VolumeInfo? {
        loadDrives().first(where: { $0.name == name })
    }
}
