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
