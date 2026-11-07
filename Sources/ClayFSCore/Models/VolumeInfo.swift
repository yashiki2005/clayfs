import Foundation

public struct RetentionPolicy: Codable, Equatable, Sendable {
    public var maxSnapshots: Int? // nil = unlimited
    public var maxAgeDays: Int?   // nil = unlimited

    public init(maxSnapshots: Int? = 50, maxAgeDays: Int? = 30) {
        self.maxSnapshots = maxSnapshots
        self.maxAgeDays = maxAgeDays
    }

    public static let `default` = RetentionPolicy(maxSnapshots: 50, maxAgeDays: 30)
    public static let unlimited = RetentionPolicy(maxSnapshots: nil, maxAgeDays: nil)
}

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
    public var autoMount: Bool
    public var retentionPolicy: RetentionPolicy

    enum CodingKeys: String, CodingKey {
        case name, bundleURL, mountURL, isMounted, sizeLimit, freeBytes, totalBytes, autoSnapshot, autoMount, retentionPolicy
    }

    public init(
        name: String,
        bundleURL: URL,
        mountURL: URL? = nil,
        isMounted: Bool = false,
        sizeLimit: String = "50g",
        freeBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        autoSnapshot: Bool = true,
        autoMount: Bool = true,
        retentionPolicy: RetentionPolicy = .default
    ) {
        self.name = name
        self.bundleURL = bundleURL
        self.mountURL = mountURL
        self.isMounted = isMounted
        self.sizeLimit = sizeLimit
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.autoSnapshot = autoSnapshot
        self.autoMount = autoMount
        self.retentionPolicy = retentionPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleURL = try container.decode(URL.self, forKey: .bundleURL)
        self.mountURL = try container.decodeIfPresent(URL.self, forKey: .mountURL)
        self.isMounted = try container.decode(Bool.self, forKey: .isMounted)
        self.sizeLimit = try container.decode(String.self, forKey: .sizeLimit)
        self.freeBytes = try container.decode(Int64.self, forKey: .freeBytes)
        self.totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        self.autoSnapshot = try container.decodeIfPresent(Bool.self, forKey: .autoSnapshot) ?? true
        self.autoMount = try container.decodeIfPresent(Bool.self, forKey: .autoMount) ?? true
        self.retentionPolicy = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retentionPolicy) ?? .default
    }
}
