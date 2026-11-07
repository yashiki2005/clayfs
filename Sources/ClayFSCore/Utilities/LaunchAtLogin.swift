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

            if !registeredViaSM {
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

    private static func installSystemdService() throws {
        let serviceURL = systemdServiceURL
        let fm = FileManager.default

        let content = """
        [Unit]
        Description=ClayFS Virtual Drives Auto-Mount Service
        After=default.target

        [Service]
        Type=oneshot
        ExecStart=/usr/local/bin/clayfs mount --all
        RemainAfterExit=yes

        [Install]
        WantedBy=default.target
        """

        try fm.createDirectory(at: serviceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: serviceURL, atomically: true, encoding: .utf8)

        // systemctl --user daemon-reload && systemctl --user enable clayfs-automount.service
        _ = try? ProcessRunner.run(executable: "/bin/systemctl", arguments: ["--user", "daemon-reload"])
        _ = try? ProcessRunner.run(executable: "/bin/systemctl", arguments: ["--user", "enable", "clayfs-automount.service"])
    }

    private static func removeSystemdService() throws {
        let serviceURL = systemdServiceURL
        _ = try? ProcessRunner.run(executable: "/bin/systemctl", arguments: ["--user", "disable", "clayfs-automount.service"])
        if FileManager.default.fileExists(atPath: serviceURL.path) {
            try FileManager.default.removeItem(at: serviceURL)
        }
        _ = try? ProcessRunner.run(executable: "/bin/systemctl", arguments: ["--user", "daemon-reload"])
    }
    #endif
}
