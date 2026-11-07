import Foundation
import ClayFSCore

@main
struct ClayFSCLIApp {
    static let version = "2.0.0-preview"

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printHelp(locale: CLILocale.detect(args: []))
            exit(0)
        }

        let cmdArgs = Array(args.dropFirst())

        do {
            switch command {
            case "create", "init":
                try handleCreate(cmdArgs)
            case "mount", "up":
                try handleMount(cmdArgs)
            case "unmount", "umount", "down":
                try handleUnmount(cmdArgs)
            case "status", "list", "info":
                try handleStatus(cmdArgs)
            case "snapshot", "commit":
                try handleSnapshot(cmdArgs)
            case "timeline", "log", "history":
                try handleTimeline(cmdArgs)
            case "diff":
                try handleDiff(cmdArgs)
            case "restore", "checkout":
                try handleRestore(cmdArgs)
            case "compact":
                try handleCompact(cmdArgs)
            case "watch":
                try handleWatch(cmdArgs)
            case "--version", "-v":
                print("clayfs version \(version)")
            case "help", "--help", "-h":
                let locale = CLILocale.detect(args: cmdArgs)
                printHelp(locale: locale)
            default:
                let locale = CLILocale.detect(args: args)
                if locale == .japanese {
                    print("エラー: 不明なコマンド '\(command)' です。'clayfs help' で使い方を表示します。")
                } else {
                    print("Error: Unknown command '\(command)'. Run 'clayfs help' for usage.")
                }
                exit(1)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Handlers

    static func handleCreate(_ args: [String]) throws {
        guard let name = args.first, !name.starts(with: "-") else {
            print("使い方: clayfs create <NAME> [--size <SIZE>] [--path <BACKEND_PATH>]")
            exit(1)
        }

        var size = "50g"
        var customPath: String?

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--size", "-s":
                if i + 1 < args.count { size = args[i + 1]; i += 1 }
            case "--path", "-p":
                if i + 1 < args.count { customPath = args[i + 1]; i += 1 }
            default:
                break
            }
            i += 1
        }

        let bundleURL: URL
        if let customPath = customPath {
            let expanded = (customPath as NSString).expandingTildeInPath
            bundleURL = URL(fileURLWithPath: expanded)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            bundleURL = home.appendingPathComponent("\(name).dmg.sparsebundle")
        }

        print("仮想ドライブを作成中: \(name) (上限: \(size))...")
        let drive = try StorageManager.shared.createDrive(name: name, size: size, bundleURL: bundleURL)
        print("作成完了: \(drive.bundleURL.path)")
        print("マウントするには: clayfs mount \(name)")
    }

    static func handleMount(_ args: [String]) throws {
        let drives = DriveRegistry.shared.loadDrives()
        let targetName = args.first(where: { !$0.starts(with: "-") })

        let targetDrive: VolumeInfo
        if let targetName = targetName {
            guard let found = drives.first(where: { $0.name == targetName }) else {
                print("エラー: ドライブ '\(targetName)' が見つかりません。")
                exit(1)
            }
            targetDrive = found
        } else if let first = drives.first {
            targetDrive = first
        } else {
            print("エラー: 登録されたドライブがありません。'clayfs create <NAME>' で作成してください。")
            exit(1)
        }

        print("マウント中: \(targetDrive.name)...")
        let mounted = try StorageManager.shared.mountDrive(bundleURL: targetDrive.bundleURL, showInFinder: true)
        print("マウント完了: \(mounted.mountURL?.path ?? "")")
        print("Finder に表示されました。作業ディレクトリ: \(mounted.mountURL?.appendingPathComponent("Workspace").path ?? "")")
    }

    static func handleUnmount(_ args: [String]) throws {
        let drives = DriveRegistry.shared.loadDrives()
        let targetName = args.first(where: { !$0.starts(with: "-") })

        guard let drive = (targetName != nil ? drives.first(where: { $0.name == targetName }) : drives.first) else {
            print("エラー: ドライブが見つかりません。")
            exit(1)
        }

        guard let mountURL = StorageManager.shared.findMountPoint(for: drive.bundleURL) else {
            print("ドライブ '\(drive.name)' はマウントされていません。")
            return
        }

        let force = args.contains("--force") || args.contains("-f")
        print("アンマウント中: \(mountURL.path)...")
        try StorageManager.shared.unmountDrive(mountURL: mountURL, force: force)
        print("アンマウント完了。")
    }

    static func handleStatus(_ args: [String]) throws {
        let drives = DriveRegistry.shared.loadDrives()
        if drives.isEmpty {
            print("登録されたドライブはありません。'clayfs create <NAME>' で作成してください。")
            return
        }

        print("=== ClayFS ドライブ一覧 ===")
        for drive in drives {
            let mountURL = StorageManager.shared.findMountPoint(for: drive.bundleURL)
            let status = (mountURL != nil) ? "マウント中 (\(mountURL!.path))" : "未マウント"
            print("• \(drive.name)")
            print("   イメージ: \(drive.bundleURL.path)")
            print("   状態:     \(status)")
            if let mURL = mountURL {
                let snapshots = (try? SnapshotManager.shared.listSnapshots(volumeMountURL: mURL, limit: 1)) ?? []
                if let latest = snapshots.first {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    print("   最新保存: \(latest.id) (\(df.string(from: latest.timestamp))) - \(latest.message)")
                }
            }
        }
    }

    static func handleSnapshot(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: マウントされている ClayFS ドライブがありません。'clayfs mount' してください。")
            exit(1)
        }

        let drives = DriveRegistry.shared.loadDrives()
        var message = "Manual snapshot"
        if let mIdx = args.firstIndex(of: "-m"), mIdx + 1 < args.count {
            message = args[mIdx + 1]
        } else {
            let nonOptions = args.filter { !$0.starts(with: "-") }
            let remaining = nonOptions.filter { arg in !drives.contains(where: { $0.name == arg }) }
            if let first = remaining.first {
                message = first
            }
        }

        print("スナップショット作成中...")
        let snap = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: message)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("保存完了: [\(snap.id)] \(snap.message)")
        print("  日時: \(df.string(from: snap.timestamp)) | ファイル数: \(snap.fileCount) | 合計サイズ: \(formatBytes(snap.totalBytes))")
    }

    static func handleTimeline(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        let snapshots = try SnapshotManager.shared.listSnapshots(volumeMountURL: mountURL, limit: 30)
        if snapshots.isEmpty {
            print("スナップショット履歴はありません。")
            return
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        print("=== スナップショット履歴 (\(snapshots.count) 件) ===")
        for s in snapshots {
            print("• \(s.id)  \(df.string(from: s.timestamp))  [\(s.author)]")
            print("    \"\(s.message)\" (ファイル数: \(s.fileCount), \(formatBytes(s.totalBytes)))")
        }
    }

    static func handleDiff(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        let drives = DriveRegistry.shared.loadDrives()
        let nonOptions = args.filter { !$0.starts(with: "-") }
        let remaining = nonOptions.filter { arg in !drives.contains(where: { $0.name == arg }) }
        let snapshotID = remaining.first

        let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL, snapshotID: snapshotID)

        if diffs.isEmpty {
            print("最後のスナップショットからの変更はありません。")
            return
        }

        print("=== 変更一覧 (\(diffs.count) 件) ===")
        for d in diffs {
            let symbol: String
            switch d.change {
            case .added: symbol = "+ [追加]"
            case .modified: symbol = "~ [変更]"
            case .deleted: symbol = "- [削除]"
            }
            print("  \(symbol) \(d.path)")
        }
    }

    static func handleRestore(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        guard let snapshotID = args.first(where: { !$0.starts(with: "-") }) else {
            print("使い方: clayfs restore <SNAPSHOT_ID> [FILE_PATH]")
            exit(1)
        }

        let subpath = args.count > 1 ? args[1] : nil
        if let subpath = subpath {
            print("復元中: [\(snapshotID)] から '\(subpath)' を復元します...")
        } else {
            print("復元中: Workspace 全体を [\(snapshotID)] の状態に復元します...")
        }

        try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snapshotID, subpath: subpath)
        print("復元完了。※復元直前の状態も安全用スナップショットとして自動保存されました。")
    }

    static func handleCompact(_ args: [String]) throws {
        let drives = DriveRegistry.shared.loadDrives()
        let targetName = args.first(where: { !$0.starts(with: "-") })
        guard let drive = (targetName != nil ? drives.first(where: { $0.name == targetName }) : drives.first) else {
            print("エラー: ドライブが見つかりません。")
            exit(1)
        }

        print("空き容量回収中 (compact): \(drive.name)...")
        try StorageManager.shared.compactDrive(bundleURL: drive.bundleURL)
        print("回収完了。")
    }

    static func handleWatch(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        let workspaceURL = mountURL.appendingPathComponent("Workspace")
        print("=== ClayFS 自動監視デーモン ===")
        print("監視フォルダ: \(workspaceURL.path)")
        print("変更後 5 秒間静穏が続くと、自動スナップショットを作成します。(Ctrl+C で停止)")

        let monitor = FSEventsMonitor(watchURL: workspaceURL, debounceSeconds: 5.0) {
            do {
                let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL)
                guard !diffs.isEmpty else { return }
                let snap = try SnapshotManager.shared.createSnapshot(
                    volumeMountURL: mountURL,
                    message: "Auto snapshot (\(diffs.count) files modified)"
                )
                print("[\(snap.id)] 自動スナップショット作成: \(snap.message)")
            } catch {
                print("自動スナップショット失敗: \(error.localizedDescription)")
            }
        }

        monitor.start()
        dispatchMain()
    }

    // MARK: - Helpers

    static func resolveActiveMount(args: [String]) -> URL? {
        let drives = DriveRegistry.shared.loadDrives()
        let cwd = FileManager.default.currentDirectoryPath

        // 1. Check if current working directory is inside a mounted volume
        for drive in drives {
            if let m = StorageManager.shared.findMountPoint(for: drive.bundleURL) {
                if cwd == m.path || cwd.hasPrefix(m.path + "/") {
                    return m
                }
            }
        }

        // 2. Check --drive <name> or -d <name>
        for opt in ["--drive", "-d"] {
            if let dIdx = args.firstIndex(of: opt), dIdx + 1 < args.count {
                let targetName = args[dIdx + 1]
                if let drive = drives.first(where: { $0.name == targetName }),
                   let m = StorageManager.shared.findMountPoint(for: drive.bundleURL) {
                    return m
                }
            }
        }

        // 3. Check if any positional argument matches a drive name
        for arg in args where !arg.starts(with: "-") {
            if let drive = drives.first(where: { $0.name == arg }),
               let m = StorageManager.shared.findMountPoint(for: drive.bundleURL) {
                return m
            }
        }

        // 4. Fallback to first mounted drive
        for drive in drives {
            if let m = StorageManager.shared.findMountPoint(for: drive.bundleURL) {
                return m
            }
        }
        return nil
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    enum CLILocale: Equatable {
        case japanese
        case english

        static func detect(args: [String]) -> CLILocale {
            // 1. Explicit CLI arguments
            if args.contains("--ja") || args.contains("-ja") || args.contains("ja") { return .japanese }
            if args.contains("--en") || args.contains("-en") || args.contains("en") { return .english }
            if let idx = args.firstIndex(of: "--lang"), idx + 1 < args.count {
                let val = args[idx + 1].lowercased()
                if val.starts(with: "ja") { return .japanese }
                if val.starts(with: "en") { return .english }
            }
            for arg in args {
                if arg.starts(with: "--lang=") {
                    let val = String(arg.dropFirst(7)).lowercased()
                    if val.starts(with: "ja") { return .japanese }
                    if val.starts(with: "en") { return .english }
                }
            }

            // 2. Environment variables (LC_ALL, LC_MESSAGES, LANG)
            let env = ProcessInfo.processInfo.environment
            let envLang = env["LC_ALL"] ?? env["LC_MESSAGES"] ?? env["LANG"] ?? ""
            let lower = envLang.lowercased()
            if lower.starts(with: "ja") { return .japanese }
            if lower.starts(with: "en") || envLang == "C" || envLang == "POSIX" { return .english }

            // 3. System Preferred Languages
            if let preferred = Locale.preferredLanguages.first?.lowercased() {
                if preferred.starts(with: "ja") { return .japanese }
            }

            return .english
        }
    }

    static func printHelp(locale: CLILocale = .japanese) {
        if locale == .japanese {
            print("""
            clayfs - 次世代 APFS 仮想ドライブ ＆ タイムマシン (v\(version))

            使い方:
              clayfs create <NAME> [--size SIZE] [--path PATH]  新しい仮想ドライブを作成
              clayfs mount [NAME]                               ドライブを Finder にマウント
              clayfs unmount [NAME]                             ドライブを安全に解除
              clayfs status                                     登録ドライブとマウント状態一覧
              clayfs snapshot [NAME] [-m MSG]                   即座にスナップショットを作成
              clayfs timeline [NAME]                            過去のスナップショット履歴一覧
              clayfs diff [NAME] [SNAPSHOT_ID]                  変更差分を表示
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        指定スナップショットの状態に復元
              clayfs compact [NAME]                             未使用バンドルブロックを回収
              clayfs watch [NAME]                               バックグラウンド自動スナップショット
              clayfs help [--lang <en|ja>]                      ヘルプ表示 (日本語 / 英語)
            """)
        } else {
            print("""
            clayfs - Next-generation APFS virtual drive & instant time machine (v\(version))

            Usage:
              clayfs create <NAME> [--size SIZE] [--path PATH]  Create a new virtual drive
              clayfs mount [NAME]                               Mount drive in Finder
              clayfs unmount [NAME]                             Safely unmount drive
              clayfs status                                     List registered drives & mount states
              clayfs snapshot [NAME] [-m MSG]                   Take an instant snapshot
              clayfs timeline [NAME]                            Show snapshot history timeline
              clayfs diff [NAME] [SNAPSHOT_ID]                  Display file change diffs
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        Restore to a specific snapshot state
              clayfs compact [NAME]                             Reclaim unused sparse bundle blocks
              clayfs watch [NAME]                               Run background auto-snapshot monitor
              clayfs help [--lang <en|ja>]                      Show help in English or Japanese
            """)
        }
    }
}
