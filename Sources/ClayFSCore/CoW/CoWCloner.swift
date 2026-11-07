import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum CoWCloner {
    /// Copies source file or directory using Copy-on-Write (reflink).
    /// On macOS: uses clonefile(2).
    /// On Linux: uses Btrfs/XFS reflink (FICLONE ioctl or cp --reflink=always).
    public static func clone(from source: URL, to destination: URL) throws {
        let srcPath = source.path
        let dstPath = destination.path

        #if os(macOS)
        let rc = Darwin.clonefile(srcPath, dstPath, 0)
        guard rc == 0 else {
            let err = errno
            throw NSError(
                domain: "ClayFSCoW",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "APFS clonefile failed from \(srcPath) to \(dstPath): \(String(cString: strerror(err)))"]
            )
        }
        #elseif os(Linux)
        // Check if source is directory or file
        var statBuf = stat()
        guard stat(srcPath, &statBuf) == 0 else {
            let err = errno
            throw NSError(
                domain: "ClayFSCoW",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "Source not found at \(srcPath): \(String(cString: strerror(err)))"]
            )
        }

        // On Linux, coreutils `cp -a --reflink=always` performs recursive atomic reflink CoW cloning,
        // preserving permissions, extended attributes, timestamps, and symlinks.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-a", "--reflink=always", srcPath, dstPath]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw NSError(
                domain: "ClayFSCoW",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Linux reflink CoW clone failed from \(srcPath) to \(dstPath): \(errStr)"]
            )
        }
        #endif
    }
}
