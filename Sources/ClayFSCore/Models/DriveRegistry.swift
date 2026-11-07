import Foundation

public final class DriveRegistry: @unchecked Sendable {
    public static let shared = DriveRegistry()

    private let configURL: URL
    private let lock = NSLock()

    public init(configURL: URL? = nil) {
        if let configURL = configURL {
            self.configURL = configURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configURL = home.appendingPathComponent(".config/clayfs/drives.json")
        }
    }

    public func loadDrives() -> [VolumeInfo] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: configURL)
            let drives = try JSONDecoder().decode([VolumeInfo].self, from: data)
            return drives
        } catch {
            return []
        }
    }

    public func saveDrives(_ drives: [VolumeInfo]) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(drives)
        try data.write(to: configURL, options: .atomic)
    }

    public func registerDrive(_ drive: VolumeInfo) throws {
        var drives = loadDrives()
        if let idx = drives.firstIndex(where: { $0.name == drive.name }) {
            drives[idx] = drive
        } else {
            drives.append(drive)
        }
        try saveDrives(drives)
    }

    public func unregisterDrive(named name: String) throws {
        var drives = loadDrives()
        drives.removeAll(where: { $0.name == name })
        try saveDrives(drives)
    }

    public func findDrive(named name: String) -> VolumeInfo? {
        loadDrives().first(where: { $0.name == name })
    }
}
