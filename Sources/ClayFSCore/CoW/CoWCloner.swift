import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum CoWCloner {
    /// Copies a file or directory tree using Copy-on-Write (reflink).
    ///
    /// On macOS `clonefile(2)` is used. Note that `clonefile` follows symbolic links: cloning a
    /// link whose target is a directory produces a copy of the target directory, not a link.
    /// That would silently turn a symlink inside the volume into a duplicated tree, and restoring
    /// the snapshot would never bring the link back. Links are therefore re-created as links, and
    /// special files (FIFOs, sockets, devices), which `clonefile` rejects with EINVAL, are skipped
    /// instead of failing the whole snapshot.
    ///
    /// On Linux, coreutils `cp -a --reflink=always` preserves links and special files.
    public static func clone(from source: URL, to destination: URL) throws {
        let srcPath = source.path
        let dstPath = destination.path

        #if os(macOS)
        var st = stat()
        guard lstat(srcPath, &st) == 0 else {
            let err = errno
            throw NSError(
                domain: "ClayFSCoW",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "Source not found at \(srcPath): \(String(cString: strerror(err)))"]
            )
        }

        let mode = st.st_mode & S_IFMT
        if mode == S_IFLNK {
            // clonefile はリンクを辿ってしまうので、リンクとして作り直す (辿り先はコピーしない)
            var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
            let n = readlink(srcPath, &buf, buf.count - 1)
            guard n >= 0 else {
                let err = errno
                throw NSError(
                    domain: "ClayFSCoW",
                    code: Int(err),
                    userInfo: [NSLocalizedDescriptionKey: "Cannot read link at \(srcPath): \(String(cString: strerror(err)))"]
                )
            }
            if symlink(buf, dstPath) != 0 {
                let err = errno
                throw NSError(
                    domain: "ClayFSCoW",
                    code: Int(err),
                    userInfo: [NSLocalizedDescriptionKey: "Cannot recreate link at \(dstPath): \(String(cString: strerror(err)))"]
                )
            }
            return
        }

        if mode != S_IFREG && mode != S_IFDIR {
            // FIFO、ソケット、デバイスは clonefile が EINVAL で断る。スナップショット全体を
            // 失敗させず、この項目だけを飛ばす (飛ばしたことは呼び手が報告する)
            throw CoWSkipError(path: srcPath, reason: "special file")
        }

        let rc = Darwin.clonefile(srcPath, dstPath, 0)
        guard rc == 0 else {
            let err = errno
            if err == EINVAL || err == ENOTSUP {
                // 一部のファイル (開いたままのデータベースなど) はクローンできない。
                // 実体のコピーに切り替える (macOS の cp はリンク・特殊ファイルを保つ)
                let cp = Process()
                cp.executableURL = URL(fileURLWithPath: "/bin/cp")
                cp.arguments = ["-pR", srcPath, dstPath]
                let errPipe = Pipe()
                cp.standardError = errPipe
                try cp.run()
                cp.waitUntilExit()
                if cp.terminationStatus == 0 { return }
                let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw NSError(
                    domain: "ClayFSCoW",
                    code: Int(cp.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "APFS clonefile and copy failed from \(srcPath) to \(dstPath): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"]
                )
            }
            throw NSError(
                domain: "ClayFSCoW",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "APFS clonefile failed from \(srcPath) to \(dstPath): \(String(cString: strerror(err)))"]
            )
        }
        #elseif os(Linux)
        // Check if source is directory or file
        var statBuf = stat()
        guard lstat(srcPath, &statBuf) == 0 else {
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

/// クローンの対象にできない項目。スナップショット全体を止めずに、この項目だけを飛ばすために使う。
public struct CoWSkipError: Error, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}
