import Foundation
#if os(macOS)
import ServiceManagement
#endif

public enum LaunchAtLogin {
    #if os(macOS)
    public static var appURL: URL {
        if Bundle.main.bundleURL.path.hasSuffix(".app") {
            return Bundle.main.bundleURL
        }

        let homeApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/ClayFS.app")
        if FileManager.default.fileExists(atPath: homeApp.path) {
            return homeApp
        }

        let systemApp = URL(fileURLWithPath: "/Applications/ClayFS.app")
        if FileManager.default.fileExists(atPath: systemApp.path) {
            return systemApp
        }

        return homeApp
    }

    public static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/top.yashiki.clayfs.app.plist")
    }

    public static var isEnabled: Bool {
        if Bundle.main.bundleURL.path.hasSuffix(".app") {
            if #available(macOS 13.0, *) {
                if SMAppService.mainApp.status == .enabled {
                    return true
                }
            }
        }
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    public static func setEnabled(_ enable: Bool) throws {
        if enable {
            var registeredViaSM = false
            if Bundle.main.bundleURL.path.hasSuffix(".app") {
                if #available(macOS 13.0, *) {
                    do {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                        registeredViaSM = true
                    } catch {
                        registeredViaSM = false
                    }
                }
            }

            if registeredViaSM {
                // SMAppService で入れたら、LaunchAgent も残っていれば外す。
                // 両方入っていると、ログイン時に 2 つ起動することになる
                try? removeLaunchAgent()
            } else {
                try installLaunchAgent()
            }
        } else {
            if Bundle.main.bundleURL.path.hasSuffix(".app") {
                if #available(macOS 13.0, *) {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                }
            }
            try removeLaunchAgent()
        }
    }

    private static func installLaunchAgent() throws {
        let plistURL = launchAgentPlistURL
        let fm = FileManager.default
        let targetApp = appURL

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>top.yashiki.clayfs.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(targetApp.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    private static func removeLaunchAgent() throws {
        let plistURL = launchAgentPlistURL
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    #elseif os(Linux)
    /// Linux では「ログイン時」に自動マウントする systemd のユーザーユニットを入れる。
    /// CLI は GUI アプリではないので、ログイン時の起動は「各ドライブの自動マウント」を指す。
    public static var systemdServiceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/systemd/user/clayfs-automount.service")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: systemdServiceURL.path)
    }

    public static func setEnabled(_ enable: Bool) throws {
        if enable {
            try installSystemdService()
        } else {
            try removeSystemdService()
        }
    }

    /// 実行中の clayfs の場所 (ユニットの ExecStart に書き込む)。
    /// /usr/local/bin に固定しない (build_linux.sh は ~/bin や ~/.local/bin にも入れる)。
    static var clayfsExecutable: String {
        let candidates = [
            "/usr/local/bin/clayfs",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/clayfs").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/clayfs").path,
        ]
        if let own = Bundle.main.executablePath, FileManager.default.isExecutableFile(atPath: own),
           URL(fileURLWithPath: own).lastPathComponent == "clayfs" {
            return own
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    private static func installSystemdService() throws {
        let serviceURL = systemdServiceURL
        let fm = FileManager.default
        let exec = clayfsExecutable

        let content = """
        [Unit]
        Description=ClayFS Virtual Drives Auto-Mount Service
        After=default.target

        [Service]
        Type=oneshot
        ExecStart=\(exec) mount --all-mounted
        RemainAfterExit=yes

        [Install]
        WantedBy=default.target
        """

        try fm.createDirectory(at: serviceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: serviceURL, atomically: true, encoding: .utf8)

        // systemctl --user daemon-reload && systemctl --user enable --now clayfs-automount.service
        let systemctl = StorageManager.toolPath("systemctl", candidates: ["/bin/systemctl", "/usr/bin/systemctl"])
        _ = try? ProcessRunner.run(executable: systemctl, arguments: ["--user", "daemon-reload"])
        _ = try? ProcessRunner.run(executable: systemctl, arguments: ["--user", "enable", "--now", "clayfs-automount.service"])
    }

    private static func removeSystemdService() throws {
        let serviceURL = systemdServiceURL
        let systemctl = StorageManager.toolPath("systemctl", candidates: ["/bin/systemctl", "/usr/bin/systemctl"])
        _ = try? ProcessRunner.run(executable: systemctl, arguments: ["--user", "disable", "--now", "clayfs-automount.service"])
        if FileManager.default.fileExists(atPath: serviceURL.path) {
            try FileManager.default.removeItem(at: serviceURL)
        }
        _ = try? ProcessRunner.run(executable: systemctl, arguments: ["--user", "daemon-reload"])
    }
    #endif
}
