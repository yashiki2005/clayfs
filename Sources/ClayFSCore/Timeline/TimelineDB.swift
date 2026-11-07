import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class TimelineDB: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbPath: String
    private let lock = NSLock()

    public init(fileURL: URL) throws {
        self.dbPath = fileURL.path
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw NSError(domain: "ClayFSTimelineDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open SQLite database: \(errMsg)"])
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 5000)
        try execute(sql: "PRAGMA journal_mode=WAL;")
        try execute(sql: "PRAGMA synchronous=NORMAL;")
        try createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS snapshots (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            message TEXT NOT NULL,
            author TEXT NOT NULL,
            file_count INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp DESC);
        """
        try execute(sql: sql)
    }

    private func execute(sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err != nil ? String(cString: err!) : "Unknown error"
            sqlite3_free(err)
            throw NSError(domain: "ClayFSTimelineDB", code: 2, userInfo: [NSLocalizedDescriptionKey: "SQLite exec error: \(msg)"])
        }
    }

    public func insertSnapshot(_ snapshot: Snapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "INSERT OR REPLACE INTO snapshots (id, timestamp, message, author, file_count, total_bytes) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ClayFSTimelineDB", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert statement"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (snapshot.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, snapshot.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (snapshot.message as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, (snapshot.author as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, Int64(snapshot.fileCount))
        sqlite3_bind_int64(stmt, 6, snapshot.totalBytes)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw NSError(domain: "ClayFSTimelineDB", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to insert snapshot row"])
        }
    }

    public func updateMetrics(id: String, fileCount: Int, totalBytes: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "UPDATE snapshots SET file_count = ?, total_bytes = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ClayFSTimelineDB", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare update metrics statement"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(fileCount))
        sqlite3_bind_int64(stmt, 2, totalBytes)
        sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw NSError(domain: "ClayFSTimelineDB", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to update snapshot metrics row"])
        }
    }

    public func getSnapshots(limit: Int = 100) -> [Snapshot] {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, timestamp, message, author, file_count, total_bytes FROM snapshots ORDER BY timestamp DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [Snapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let ts = sqlite3_column_double(stmt, 1)
            let msg = String(cString: sqlite3_column_text(stmt, 2))
            let author = String(cString: sqlite3_column_text(stmt, 3))
            let fileCount = Int(sqlite3_column_int64(stmt, 4))
            let totalBytes = sqlite3_column_int64(stmt, 5)

            results.append(Snapshot(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                message: msg,
                author: author,
                fileCount: fileCount,
                totalBytes: totalBytes
            ))
        }
        return results
    }

    public func findSnapshot(id: String) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, timestamp, message, author, file_count, total_bytes FROM snapshots WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let sid = String(cString: sqlite3_column_text(stmt, 0))
            let ts = sqlite3_column_double(stmt, 1)
            let msg = String(cString: sqlite3_column_text(stmt, 2))
            let author = String(cString: sqlite3_column_text(stmt, 3))
            let fileCount = Int(sqlite3_column_int64(stmt, 4))
            let totalBytes = sqlite3_column_int64(stmt, 5)

            return Snapshot(
                id: sid,
                timestamp: Date(timeIntervalSince1970: ts),
                message: msg,
                author: author,
                fileCount: fileCount,
                totalBytes: totalBytes
            )
        }
        return nil
    }

    public func deleteSnapshot(id: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM snapshots WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ClayFSTimelineDB", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare delete statement"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw NSError(domain: "ClayFSTimelineDB", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to delete snapshot row"])
        }
    }
}
