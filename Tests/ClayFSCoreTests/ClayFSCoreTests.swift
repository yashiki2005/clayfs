import Testing
import Foundation
@testable import ClayFSCore

@Test func testDriveRegistry() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let configURL = tempDir.appendingPathComponent("drives.json")
    let registry = DriveRegistry(configURL: configURL)

    #expect(registry.loadDrives().isEmpty)

    let bundleURL = tempDir.appendingPathComponent("TestDrive.sparsebundle")
    let drive = VolumeInfo(name: "TestDrive", bundleURL: bundleURL, sizeLimit: "10g")
    try registry.registerDrive(drive)

    let loaded = registry.loadDrives()
    #expect(loaded.count == 1)
    #expect(loaded.first?.name == "TestDrive")
}

@Test func testTimelineDB() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_db_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("timeline.sqlite3")
    let db = try TimelineDB(fileURL: dbURL)

    let snap = Snapshot(id: "20261108_050000", message: "Initial snapshot", fileCount: 42, totalBytes: 1024)
    try db.insertSnapshot(snap)

    let list = db.getSnapshots()
    #expect(list.count == 1)
    #expect(list.first?.id == "20261108_050000")
    #expect(list.first?.message == "Initial snapshot")
    #expect(list.first?.fileCount == 42)
}

@Test func testTimelineDBStringBindingLifetime() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_binding_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("timeline.sqlite3")
    let db = try TimelineDB(fileURL: dbURL)

    // Insert 50 snapshots with temporary dynamically formatted strings
    for i in 1...50 {
        let dynamicId = "snap_\(UUID().uuidString.prefix(8))_\(i)"
        let dynamicMsg = "Dynamic commit message with unicode: 🚀 リファクタリング #\(i)"
        let dynamicAuthor = "Author_\(UUID().uuidString.prefix(4))"
        let snap = Snapshot(id: dynamicId, message: dynamicMsg, author: dynamicAuthor, fileCount: i, totalBytes: Int64(i * 100))
        try db.insertSnapshot(snap)
    }

    let all = db.getSnapshots(limit: 100)
    #expect(all.count == 50)
    for s in all {
        #expect(s.message.contains("🚀 リファクタリング"))
        #expect(!s.id.isEmpty)
    }
}

@Test func testDriveRegistryCorruptionProtection() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_corrupt_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let configURL = tempDir.appendingPathComponent("drives.json")
    let registry = DriveRegistry(configURL: configURL)

    // 1. Register a valid drive
    let drive1 = VolumeInfo(name: "ValidDrive", bundleURL: tempDir.appendingPathComponent("Valid.sparsebundle"))
    try registry.registerDrive(drive1)
    #expect(registry.loadDrives().count == 1)

    // 2. Corrupt the file with invalid JSON content
    let invalidJSON = "{ this is completely corrupted json !!! }}}"
    try invalidJSON.write(to: configURL, atomically: true, encoding: .utf8)

    // 3. Attempting to register another drive should throw an error and back up corrupted file
    let drive2 = VolumeInfo(name: "AnotherDrive", bundleURL: tempDir.appendingPathComponent("Another.sparsebundle"))
    var didThrow = false
    do {
        try registry.registerDrive(drive2)
    } catch {
        didThrow = true
    }
    #expect(didThrow)

    // Verify backup file exists
    let files = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
    let hasCorruptedBackup = files.contains { $0.contains("drives.json.corrupted") }
    #expect(hasCorruptedBackup)
}

@Test func testEndToEndVirtualDriveWorkflow() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_e2e_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let bundleURL = tempDir.appendingPathComponent("E2EDrive.sparsebundle")
    let driveName = "E2ETest_\(UUID().uuidString.prefix(6))"

    // 1. Create 500m drive (isolated from user registry)
    let drive = try StorageManager.shared.createDrive(name: driveName, size: "500m", bundleURL: bundleURL, register: false)
    #expect(FileManager.default.fileExists(atPath: drive.bundleURL.path))

    // 2. Mount drive
    let mounted = try StorageManager.shared.mountDrive(bundleURL: drive.bundleURL, showInFinder: false, register: false)
    guard let mountURL = mounted.mountURL else {
        Issue.record("Failed to mount drive")
        return
    }

    defer {
        try? StorageManager.shared.unmountDrive(mountURL: mountURL, force: true)
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // 3. Write file directly into Volume root
    let docURL = mountURL.appendingPathComponent("document.txt")
    try "Version 1 content".write(to: docURL, atomically: true, encoding: .utf8)

    // 4. Create snapshot 1
    let snap1 = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: "Initial commit")
    #expect(snap1.fileCount == 1)

    // 5. Modify file and add another file
    try "Version 2 modified content".write(to: docURL, atomically: true, encoding: .utf8)
    let newDocURL = mountURL.appendingPathComponent("notes.md")
    try "# Notes".write(to: newDocURL, atomically: true, encoding: .utf8)

    // 6. Check diff
    let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL, snapshotID: snap1.id)
    #expect(diffs.count == 2)

    let modifiedDiff = diffs.first(where: { $0.path == "document.txt" })
    #expect(modifiedDiff?.change == .modified)

    let addedDiff = diffs.first(where: { $0.path == "notes.md" })
    #expect(addedDiff?.change == .added)

    // 7. Create snapshot 2
    let snap2 = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: "Updated notes")
    #expect(snap2.fileCount == 2)

    // 8. Restore to snapshot 1
    try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snap1.id)

    // Verify document.txt reverted to Version 1 and notes.md is gone
    let restoredContent = try String(contentsOf: docURL, encoding: .utf8)
    #expect(restoredContent == "Version 1 content")
    #expect(!FileManager.default.fileExists(atPath: newDocURL.path))
}

@Test func testTimelineDBWALMode() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_wal_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("timeline.sqlite3")
    let db = try TimelineDB(fileURL: dbURL)

    // Inserting a snapshot should write in WAL mode
    let snap = Snapshot(id: "snap_wal_1", message: "WAL Test", fileCount: 1, totalBytes: 100)
    try db.insertSnapshot(snap)

    let shmExists = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("timeline.sqlite3-shm").path)
    let walExists = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("timeline.sqlite3-wal").path)
    #expect(shmExists || walExists)
}

@Test func testRestoreSubpathTraversalSecurity() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_sec_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bundleURL = tempDir.appendingPathComponent("SecDrive.sparsebundle")
    let driveName = "SecTest_\(UUID().uuidString.prefix(6))"

    let drive = try StorageManager.shared.createDrive(name: driveName, size: "300m", bundleURL: bundleURL, register: false)
    let mounted = try StorageManager.shared.mountDrive(bundleURL: drive.bundleURL, showInFinder: false, register: false)
    guard let mountURL = mounted.mountURL else {
        Issue.record("Failed to mount security test drive")
        return
    }

    defer {
        try? StorageManager.shared.unmountDrive(mountURL: mountURL, force: true)
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // Write a normal file and take snapshot
    let testDoc = mountURL.appendingPathComponent("safe.txt")
    try "Safe content".write(to: testDoc, atomically: true, encoding: .utf8)
    let snap = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: "Sec commit")

    // 1. Path traversal outside volume must throw
    var didBlockTraversal = false
    do {
        try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snap.id, subpath: "../../../etc/passwd")
    } catch {
        didBlockTraversal = true
    }
    #expect(didBlockTraversal)

    // 2. Modifying .clayfs must throw
    var didBlockSystemDir = false
    do {
        try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snap.id, subpath: ".clayfs/timeline.sqlite3")
    } catch {
        didBlockSystemDir = true
    }
    #expect(didBlockSystemDir)
}

@Test func testDotfileDetectionInDiff() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_dot_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bundleURL = tempDir.appendingPathComponent("DotDrive.sparsebundle")
    let driveName = "DotTest_\(UUID().uuidString.prefix(6))"

    let drive = try StorageManager.shared.createDrive(name: driveName, size: "300m", bundleURL: bundleURL, register: false)
    let mounted = try StorageManager.shared.mountDrive(bundleURL: drive.bundleURL, showInFinder: false, register: false)
    guard let mountURL = mounted.mountURL else {
        Issue.record("Failed to mount dotfile test drive")
        return
    }

    defer {
        try? StorageManager.shared.unmountDrive(mountURL: mountURL, force: true)
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // 1. Initial snapshot with empty volume
    let snap0 = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: "Initial empty")

    // 2. Add dotfiles: .gitignore, .env, .github/workflow.yml
    let gitignoreURL = mountURL.appendingPathComponent(".gitignore")
    try "*.tmp\n.DS_Store".write(to: gitignoreURL, atomically: true, encoding: .utf8)

    let envURL = mountURL.appendingPathComponent(".env")
    try "SECRET_KEY=12345".write(to: envURL, atomically: true, encoding: .utf8)

    let githubDir = mountURL.appendingPathComponent(".github")
    try FileManager.default.createDirectory(at: githubDir, withIntermediateDirectories: true)
    let ciURL = githubDir.appendingPathComponent("ci.yml")
    try "name: CI".write(to: ciURL, atomically: true, encoding: .utf8)

    // 3. Diff must detect all 3 dotfiles!
    let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL, snapshotID: snap0.id)
    let paths = diffs.map { $0.path }
    #expect(paths.contains(".gitignore"))
    #expect(paths.contains(".env"))
    #expect(paths.contains(".github/ci.yml"))

    // 4. Create snapshot with dotfiles and verify fileCount
    let snap1 = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: "Added dotfiles")
    #expect(snap1.fileCount == 3)
}
