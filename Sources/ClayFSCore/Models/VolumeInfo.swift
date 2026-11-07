import Foundation

public struct VolumeInfo: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let bundleURL: URL
    public var mountURL: URL?
    public var isMounted: Bool
    public var sizeLimit: String
    public var freeBytes: Int64
    public var totalBytes: Int64
    public var autoSnapshot: Bool

    public init(
        name: String,
        bundleURL: URL,
        mountURL: URL? = nil,
        isMounted: Bool = false,
        sizeLimit: String = "50g",
        freeBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        autoSnapshot: Bool = true
    ) {
        self.name = name
        self.bundleURL = bundleURL
        self.mountURL = mountURL
        self.isMounted = isMounted
        self.sizeLimit = sizeLimit
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.autoSnapshot = autoSnapshot
    }
}
