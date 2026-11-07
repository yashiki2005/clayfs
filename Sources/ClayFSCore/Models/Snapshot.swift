import Foundation

public struct Snapshot: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let message: String
    public let author: String
    public let fileCount: Int
    public let totalBytes: Int64

    public init(
        id: String,
        timestamp: Date = Date(),
        message: String,
        author: String = NSUserName(),
        fileCount: Int = 0,
        totalBytes: Int64 = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.author = author
        self.fileCount = fileCount
        self.totalBytes = totalBytes
    }
}

public struct FileDiff: Codable, Sendable {
    public enum ChangeType: String, Codable, Sendable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
    }

    public let path: String
    public let change: ChangeType
    public let size: Int64

    public init(path: String, change: ChangeType, size: Int64 = 0) {
        self.path = path
        self.change = change
        self.size = size
    }
}
