import Testing
import Foundation
@testable import ClayFSCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// ディスクイメージを作る統合テスト (createDrive → mountDrive → snapshot → restore) は、
// hdiutil (macOS) と sparsebundle を前提にしている。Linux では走らせない。
// Linux 側の試験は linux/test_btrfs.sh (要 root / btrfs) と linux/test_parse_dump.py
// (btrfs なしで動く) が受け持つ。
#if os(macOS)
private let canCreateImages = true
#else
private let canCreateImages = false
#endif

/// イメージを作れない環境では、理由を添えて飛ばす (失敗にしない)。
private func requiresDiskImages() throws {
    try #require(canCreateImages, "ディスクイメージを作る試験は macOS の hdiutil が要ります (Linux では linux/ の試験を使う)")
}

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
    try requiresDiskImages()
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
    try requiresDiskImages()
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
    try requiresDiskImages()
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

// MARK: - ディスクイメージを作らない試験 (Linux でも動く)

@Test func testCoWCloneKeepsSymlink() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_cow_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // リンク先のディレクトリ (スナップショットには含めたくない)
    let realDir = tempDir.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
    try "v1".write(to: realDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    let link = tempDir.appendingPathComponent("mylink")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDir)

    let dest = tempDir.appendingPathComponent("mylink_copy")
    try CoWCloner.clone(from: link, to: dest)

    // clonefile はリンクを辿るので、そのまま使うと「ディレクトリの複製」になる。
    // clone はリンクをリンクとして作り直す (辿らない) ことを確かめる
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: dest.path)
    #expect(target == realDir.path)
    // 複製も「リンク」であること (fileExists はリンクを辿るので、lstat で型を見る)
    var st = stat()
    #expect(lstat(dest.path, &st) == 0)
    #expect((st.st_mode & S_IFMT) == S_IFLNK)
}

@Test func testCoWCloneSkipsFifoWithoutFailing() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_fifo_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fifo = tempDir.appendingPathComponent("pipe")
    guard mkfifo(fifo.path, 0o644) == 0 else { return }

    let dest = tempDir.appendingPathComponent("pipe_copy")
    var skipped = false
    do {
        try CoWCloner.clone(from: fifo, to: dest)
    } catch is CoWSkipError {
        skipped = true
    }
    // クローンできない項目は、スナップショット全体を止めずに「飛ばす」として返す
    #expect(skipped)
    #expect(!FileManager.default.fileExists(atPath: dest.path))
}

@Test func testMountFieldUnescaping() {
    // /proc/mounts は空白を \040 で書く。空白を含むマウント先と、登録済みのパスを一致させるために解く
    #expect(StorageManager.unescapeMountField("/media/u/my\\040drive") == "/media/u/my drive")
    #expect(StorageManager.unescapeMountField("/media/u/plain") == "/media/u/plain")
    #expect(StorageManager.unescapeMountField("/mnt/a\\040b/c\\011d") == "/mnt/a b/c\td")
}

@Test func testSnapshotSkipsFifoAndKeepsSymlink() throws {
    // hdiutil を使わない: 普通のディレクトリを「ボリューム」としてスナップショットの振る舞いだけを確かめる
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("clayfs_snap_\(UUID().uuidString)")
    let volURL = base.appendingPathComponent("vol")
    try FileManager.default.createDirectory(at: volURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    try "doc".write(to: volURL.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    let outside = base.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try "secret".write(to: outside.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: volURL.appendingPathComponent("link"), withDestinationURL: outside)
    let fifoCreated = mkfifo(volURL.appendingPathComponent("pipe").path, 0o644) == 0

    let sm = SnapshotManager()
    let snap = try sm.createSnapshot(volumeMountURL: volURL, message: "link and fifo", sync: true)
    let snapDir = volURL.appendingPathComponent(".clayfs/snapshots").appendingPathComponent(snap.id)

    var st = stat()
    #expect(lstat(snapDir.appendingPathComponent("link").path, &st) == 0)
    #expect((st.st_mode & S_IFMT) == S_IFLNK)          // リンクはリンクとして残す (辿った複製にしない)
    #expect(FileManager.default.fileExists(atPath: snapDir.appendingPathComponent("doc.txt").path))
    if fifoCreated {
        // クローンできない FIFO は、スナップショット全体を止めずに飛ばす
        #expect(lstat(snapDir.appendingPathComponent("pipe").path, &st) != 0)
    }

    // 復元してもリンクのまま戻る
    try "changed".write(to: volURL.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try sm.restore(volumeMountURL: volURL, snapshotID: snap.id, sync: true)
    let restored = try String(contentsOf: volURL.appendingPathComponent("doc.txt"), encoding: .utf8)
    #expect(restored == "doc")
    #expect(lstat(volURL.appendingPathComponent("link").path, &st) == 0)
    #expect((st.st_mode & S_IFMT) == S_IFLNK)
}
