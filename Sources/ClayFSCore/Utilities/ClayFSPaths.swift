import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum ClayFSPaths {
    /// Returns the effective user's home directory.
    /// When executed via `sudo`, resolves to the invoking user's home directory ($SUDO_USER)
    /// rather than `/root`.
    public static var effectiveHomeDirectory: URL {
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"], !sudoUser.isEmpty {
            #if os(macOS) || os(Linux)
            if let pw = getpwnam(sudoUser) {
                let homePath = String(cString: pw.pointee.pw_dir)
                if !homePath.isEmpty {
                    return URL(fileURLWithPath: homePath)
                }
            }
            #endif
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Fixes ownership of the mount point and metadata on Linux so the regular user can read/write without sudo.
    public static func ensureUserOwnership(at url: URL, recursive: Bool = true) {
        #if os(Linux)
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"], !sudoUser.isEmpty, let pw = getpwnam(sudoUser) {
            let uid = pw.pointee.pw_uid
            let gid = pw.pointee.pw_gid
            chown(url.path, uid, gid)
            chmod(url.path, 0o755)

            if recursive {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        chown(fileURL.path, uid, gid)
                    }
                }
            }
        }
        #endif
    }
}
