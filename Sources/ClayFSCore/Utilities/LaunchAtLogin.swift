import Foundation
import ServiceManagement

public enum LaunchAtLogin {
    public static var appURL: URL {
        // 1. If currently running inside ClayFS.app
        if Bundle.main.bundleURL.path.hasSuffix(".app") {
            return Bundle.main.bundleURL
        }

        // 2. User Applications
        let homeApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/ClayFS.app")
        if FileManager.default.fileExists(atPath: homeApp.path) {
            return homeApp
        }

        // 3. System Applications
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
        // 1. Check SMAppService if inside app
        if Bundle.main.bundleURL.path.hasSuffix(".app") {
            if #available(macOS 13.0, *) {
                if SMAppService.mainApp.status == .enabled {
                    return true
                }
            }
        }

        // 2. Check LaunchAgent plist
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
                        // Fallback to LaunchAgent if SMAppService fails (e.g., ad-hoc signature outside /Applications)
                        registeredViaSM = false
                    }
                }
            }

            if !registeredViaSM {
                try installLaunchAgent()
            }
        } else {
            // Disable both SMAppService and LaunchAgent
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
}
