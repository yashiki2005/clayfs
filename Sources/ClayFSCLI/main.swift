import Foundation
import ClayFSCore
#if os(Linux)
import Dispatch
#endif

@main
struct ClayFSCLIApp {
    static let version = "2.0.0-preview"

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printHelp(language: AppLanguage.detect(cliArgs: []))
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
            case "prune":
                try handlePrune(cmdArgs)
            case "autostart":
                try handleAutostart(cmdArgs)
            case "automount":
                try handleAutomount(cmdArgs)
            case "watch":
                try handleWatch(cmdArgs)
            case "--version", "-v":
                print("clayfs version \(version)")
            case "help", "--help", "-h":
                let lang = AppLanguage.detect(cliArgs: cmdArgs)
                printHelp(language: lang)
            default:
                let lang = AppLanguage.detect(cliArgs: args)
                switch lang {
                case .japanese:
                    print("エラー: 不明なコマンド '\(command)' です。'clayfs help' で使い方を表示します。")
                case .simplifiedChinese:
                    print("错误: 未知命令 '\(command)'。运行 'clayfs help' 查看用法。")
                case .traditionalChinese:
                    print("錯誤: 未知命令 '\(command)'。執行 'clayfs help' 檢視用法。")
                case .spanish:
                    print("Error: Comando desconocido '\(command)'. Ejecute 'clayfs help' para ver el uso.")
                case .french:
                    print("Erreur : Commande inconnue '\(command)'. Exécutez 'clayfs help' pour voir l'utilisation.")
                case .german:
                    print("Fehler: Unbekannter Befehl '\(command)'. Führen Sie 'clayfs help' aus, um die Hilfe anzuzeigen.")
                case .korean:
                    print("오류: 알 수 없는 명령 '\(command)'입니다. 'clayfs help'를 실행하여 사용법을 확인하십시오.")
                case .english:
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
            let home = ClayFSPaths.effectiveHomeDirectory
            #if os(macOS)
            bundleURL = home.appendingPathComponent("\(name).dmg.sparsebundle")
            #elseif os(Linux)
            let disksDir = home.appendingPathComponent(".clayfs/disks")
            bundleURL = disksDir.appendingPathComponent("\(name).img")
            #endif
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
        #if os(macOS)
        print("Finder に表示されました。作業ディレクトリ: \(mounted.mountURL?.path ?? "")")
        #elseif os(Linux)
        print("作業ディレクトリ: \(mounted.mountURL?.path ?? "")")
        #endif
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
            print("   イメージ:     \(drive.bundleURL.path)")
            print("   状態:         \(status)")
            print("   自動マウント: \(drive.autoMount ? "有効 (ON)" : "無効 (OFF)")")
            if let mURL = mountURL {
                let snapshots = (try? SnapshotManager.shared.listSnapshots(volumeMountURL: mURL, limit: 1)) ?? []
                if let latest = snapshots.first {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    print("   最新保存:     \(latest.id) (\(df.string(from: latest.timestamp))) - \(latest.message)")
                }
            }
        }

        let autostart = LaunchAtLogin.isEnabled ? "有効 (ON)" : "無効 (OFF)"
        print("---")
        print("ログイン時の ClayFS 自動起動: \(autostart)")
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
        let targetName = args.first(where: { !$0.starts(with: "-") && $0 != message })
        let targetDrive = targetName != nil ? drives.first(where: { $0.name == targetName }) : drives.first
        let snap = try SnapshotManager.shared.createSnapshot(
            volumeMountURL: mountURL,
            message: message,
            policy: targetDrive?.retentionPolicy ?? .default,
            sync: true
        )
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

        let drives = DriveRegistry.shared.loadDrives()
        var nonOptions = args.filter { !$0.starts(with: "-") }
        if let first = nonOptions.first, drives.contains(where: { $0.name == first }) || first.hasPrefix("/Volumes/") {
            nonOptions.removeFirst()
        }

        guard let snapshotID = nonOptions.first else {
            print("使い方: clayfs restore [DRIVE_NAME] <SNAPSHOT_ID> [FILE_PATH]")
            exit(1)
        }

        let subpath = nonOptions.count > 1 ? nonOptions[1] : nil
        if let subpath = subpath {
            print("復元中: [\(snapshotID)] から '\(subpath)' を復元します...")
        } else {
            print("復元中: ドライブ全体を [\(snapshotID)] の状態に復元します...")
        }

        try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snapshotID, subpath: subpath, sync: true)
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

    static func handlePrune(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        var maxSnapshots: Int? = 50
        var maxAgeDays: Int? = 30

        var i = 0
        while i < args.count {
            let arg = args[i]
            if (arg == "--keep" || arg == "--count" || arg == "-k") && i + 1 < args.count {
                guard let val = Int(args[i + 1]), val >= 0 else {
                    print("エラー: --keep には 0 以上の整数を指定してください。'\(args[i + 1])'")
                    exit(1)
                }
                maxSnapshots = val
                i += 1
            } else if arg.starts(with: "--keep=") {
                let raw = String(arg.dropFirst(7))
                guard let val = Int(raw), val >= 0 else {
                    print("エラー: --keep には 0 以上の整数を指定してください。'\(raw)'")
                    exit(1)
                }
                maxSnapshots = val
            } else if (arg == "--days" || arg == "-d") && i + 1 < args.count {
                guard let val = Int(args[i + 1]), val >= 0 else {
                    print("エラー: --days には 0 以上の整数を指定してください。'\(args[i + 1])'")
                    exit(1)
                }
                maxAgeDays = val
                i += 1
            } else if arg.starts(with: "--days=") {
                let raw = String(arg.dropFirst(7))
                guard let val = Int(raw), val >= 0 else {
                    print("エラー: --days には 0 以上の整数を指定してください。'\(raw)'")
                    exit(1)
                }
                maxAgeDays = val
            } else if arg == "--unlimited-count" {
                maxSnapshots = nil
            } else if arg == "--unlimited-days" {
                maxAgeDays = nil
            }
            i += 1
        }

        let policy = RetentionPolicy(maxSnapshots: maxSnapshots, maxAgeDays: maxAgeDays)
        let drives = DriveRegistry.shared.loadDrives()
        let targetName = args.first(where: { !$0.starts(with: "-") })
        if let target = (targetName != nil ? drives.first(where: { $0.name == targetName }) : drives.first) {
            var updated = target
            updated.retentionPolicy = policy
            try? DriveRegistry.shared.registerDrive(updated)
        }

        let countDesc = maxSnapshots.map { "\($0) 件" } ?? "無制限"
        let daysDesc = maxAgeDays.map { "\($0) 日" } ?? "無制限"
        print("スナップショット履歴の整理を実行中 (上限: \(countDesc), 期限: \(daysDesc))...")

        let pruned = try SnapshotManager.shared.pruneSnapshots(volumeMountURL: mountURL, policy: policy, sync: true)
        if pruned.isEmpty {
            print("整理対象の古いスナップショットはありませんでした。")
        } else {
            print("整理完了: \(pruned.count) 件の古いスナップショットを削除しました。")
            for p in pruned {
                print("  - [削除] \(p.id): \(p.message)")
            }
        }
    }

    static func handleAutostart(_ args: [String]) throws {
        if let mode = args.first?.lowercased() {
            if mode == "on" || mode == "enable" || mode == "true" || mode == "1" {
                try LaunchAtLogin.setEnabled(true)
                print("ログイン時の ClayFS 自動起動を有効にしました。")
            } else if mode == "off" || mode == "disable" || mode == "false" || mode == "0" {
                try LaunchAtLogin.setEnabled(false)
                print("ログイン時の ClayFS 自動起動を無効にしました。")
            } else {
                print("使い方: clayfs autostart [on|off]")
            }
        } else {
            let status = LaunchAtLogin.isEnabled ? "有効 (ON)" : "無効 (OFF)"
            print("ログイン時の ClayFS 自動起動: \(status)")
            print("切り替えるには: clayfs autostart [on|off]")
        }
    }

    static func handleAutomount(_ args: [String]) throws {
        let drives = DriveRegistry.shared.loadDrives()
        if drives.isEmpty {
            print("エラー: 登録されたドライブがありません。'clayfs create <NAME>' で作成してください。")
            exit(1)
        }

        let nonFlags = args.filter { !$0.starts(with: "-") }
        let targetName = nonFlags.first(where: { name in drives.contains(where: { $0.name == name }) })
        let target = (targetName != nil ? drives.first(where: { $0.name == targetName }) : drives.first)!

        let modeArg = nonFlags.first(where: { $0 != target.name })

        if let mode = modeArg?.lowercased() {
            var updated = target
            if mode == "on" || mode == "enable" || mode == "true" || mode == "1" {
                updated.autoMount = true
                try DriveRegistry.shared.registerDrive(updated)
                print("ドライブ '\(target.name)' の起動時自動マウントを有効にしました。")
            } else if mode == "off" || mode == "disable" || mode == "false" || mode == "0" {
                updated.autoMount = false
                try DriveRegistry.shared.registerDrive(updated)
                print("ドライブ '\(target.name)' の起動時自動マウントを無効にしました。")
            } else {
                print("使い方: clayfs automount [DRIVE] [on|off]")
            }
        } else {
            let status = target.autoMount ? "有効 (ON)" : "無効 (OFF)"
            print("ドライブ '\(target.name)' の起動時自動マウント: \(status)")
            print("切り替えるには: clayfs automount \(target.name) [on|off]")
        }
    }

    static func handleWatch(_ args: [String]) throws {
        guard let mountURL = resolveActiveMount(args: args) else {
            print("エラー: ドライブがマウントされていません。")
            exit(1)
        }

        let drives = DriveRegistry.shared.loadDrives()
        let targetDrive = drives.first(where: {
            if let m = StorageManager.shared.findMountPoint(for: $0.bundleURL) {
                return m.standardizedFileURL == mountURL.standardizedFileURL
            }
            return false
        })
        let policy = targetDrive?.retentionPolicy ?? .default

        print("=== ClayFS 自動監視デーモン ===")
        print("監視フォルダ: \(mountURL.path)")
        print("変更後 5 秒間静穏が続くと、自動スナップショットを作成します。(Ctrl+C で停止)")

        #if canImport(CoreServices)
        let monitor = FSEventsMonitor(watchURL: mountURL, debounceSeconds: 5.0) {
            do {
                let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL)
                guard !diffs.isEmpty else { return }
                let snap = try SnapshotManager.shared.createSnapshot(
                    volumeMountURL: mountURL,
                    message: "Auto snapshot (\(diffs.count) files modified)",
                    policy: policy
                )
                print("[\(snap.id)] 自動スナップショット作成: \(snap.message)")
            } catch {
                print("自動スナップショット失敗: \(error.localizedDescription)")
            }
        }
        monitor.start()
        #else
        let monitor = PollingMonitor(watchURL: mountURL, interval: 5.0) {
            do {
                let diffs = try SnapshotManager.shared.diff(volumeMountURL: mountURL)
                guard !diffs.isEmpty else { return }
                let snap = try SnapshotManager.shared.createSnapshot(
                    volumeMountURL: mountURL,
                    message: "Auto snapshot (\(diffs.count) files modified)",
                    policy: policy
                )
                print("[\(snap.id)] 自動スナップショット作成: \(snap.message)")
            } catch {
                print("自動スナップショット失敗: \(error.localizedDescription)")
            }
        }
        monitor.start()
        #endif
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

    static func printHelp(language: AppLanguage = AppLanguage.detect()) {
        switch language {
        case .japanese:
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
              clayfs prune [NAME] [--keep N] [--days N]         古いスナップショット履歴を整理
              clayfs autostart [on|off]                         ログイン時の ClayFS 自動起動を設定
              clayfs automount [NAME] [on|off]                  起動時のドライブ自動マウントを設定
              clayfs watch [NAME]                               バックグラウンド自動スナップショット
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       多言語ヘルプ表示
            """)
        case .simplifiedChinese:
            print("""
            clayfs - 下一代 APFS 虚拟驱动器与即时时光机 (v\(version))

            用法:
              clayfs create <NAME> [--size SIZE] [--path PATH]  创建新的虚拟驱动器
              clayfs mount [NAME]                               在访达 (Finder) 中挂载驱动器
              clayfs unmount [NAME]                             安全卸载驱动器
              clayfs status                                     列出已注册驱动器及挂载状态
              clayfs snapshot [NAME] [-m MSG]                   即时创建快照
              clayfs timeline [NAME]                            查看快照历史时间线
              clayfs diff [NAME] [SNAPSHOT_ID]                  显示文件变更差异
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        恢复到指定快照状态
              clayfs compact [NAME]                             压缩并回收未使用的存储空间
              clayfs prune [NAME] [--keep N] [--days N]         清理过期的快照历史
              clayfs autostart [on|off]                         设置开机登录时自动启动 ClayFS
              clayfs automount [NAME] [on|off]                  设置开机时驱动器自动挂载
              clayfs watch [NAME]                               后台自动快照监控
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       显示多语言帮助
            """)
        case .traditionalChinese:
            print("""
            clayfs - 下一代 APFS 虛擬磁碟與即時時光機 (v\(version))

            用法:
              clayfs create <NAME> [--size SIZE] [--path PATH]  建立新的虛擬磁碟
              clayfs mount [NAME]                               在 Finder 中掛載磁碟
              clayfs unmount [NAME]                             安全卸載磁碟
              clayfs status                                     列出已註冊磁碟及掛載狀態
              clayfs snapshot [NAME] [-m MSG]                   即時建立快照
              clayfs timeline [NAME]                            檢視快照歷史時間線
              clayfs diff [NAME] [SNAPSHOT_ID]                  顯示檔案變更差異
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        還原至指定快照狀態
              clayfs compact [NAME]                             壓縮並回收未使用的儲存空間
              clayfs prune [NAME] [--keep N] [--days N]         清理過期的快照歷史
              clayfs autostart [on|off]                         設定開機登入時自動啟動 ClayFS
              clayfs automount [NAME] [on|off]                  設定開機時磁碟自動掛載
              clayfs watch [NAME]                               背景自動快照監控
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       顯示多語言說明
            """)
        case .spanish:
            print("""
            clayfs - Unidad virtual APFS de nueva generación y máquina del tiempo instantánea (v\(version))

            Uso:
              clayfs create <NAME> [--size SIZE] [--path PATH]  Crear una nueva unidad virtual
              clayfs mount [NAME]                               Montar la unidad en Finder
              clayfs unmount [NAME]                             Desmontar la unidad de forma segura
              clayfs status                                     Listar unidades registradas y estados
              clayfs snapshot [NAME] [-m MSG]                   Tomar una instantánea inmediata
              clayfs timeline [NAME]                            Mostrar historial de instantáneas
              clayfs diff [NAME] [SNAPSHOT_ID]                  Mostrar diferencias de archivos
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        Restaurar al estado de una instantánea
              clayfs compact [NAME]                             Recuperar espacio no utilizado
              clayfs prune [NAME] [--keep N] [--days N]         Purgar historial de instantáneas antiguas
              clayfs autostart [on|off]                         Configurar inicio automático al iniciar sesión
              clayfs automount [NAME] [on|off]                  Configurar montaje automático de unidad al iniciar
              clayfs watch [NAME]                               Monitor de instantáneas automáticas
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       Mostrar ayuda en varios idiomas
            """)
        case .french:
            print("""
            clayfs - Disque virtuel APFS nouvelle génération et machine à remonter le temps instantanée (v\(version))

            Utilisation:
              clayfs create <NAME> [--size SIZE] [--path PATH]  Créer un nouveau disque virtuel
              clayfs mount [NAME]                               Monter le disque dans le Finder
              clayfs unmount [NAME]                             Démonter le disque en toute sécurité
              clayfs status                                     Lister les disques enregistrés et leur état
              clayfs snapshot [NAME] [-m MSG]                   Prendre un instantané immédiat
              clayfs timeline [NAME]                            Afficher la chronologie des instantanés
              clayfs diff [NAME] [SNAPSHOT_ID]                  Afficher les différences de fichiers
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        Restaurer à l'état d'un instantané
              clayfs compact [NAME]                             Récupérer l'espace disque inutilisé
              clayfs prune [NAME] [--keep N] [--days N]         Purger les anciens instantanés
              clayfs autostart [on|off]                         Activer/désactiver le démarrage automatique
              clayfs automount [NAME] [on|off]                  Activer/désactiver le montage automatique au démarrage
              clayfs watch [NAME]                               Surveillance automatique en arrière-plan
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       Afficher l'aide multilingue
            """)
        case .german:
            print("""
            clayfs - APFS-Virtuallaufwerk der nächsten Generation & Sofort-Zeitreise (v\(version))

            Verwendung:
              clayfs create <NAME> [--size SIZE] [--path PATH]  Neues virtuelles Laufwerk erstellen
              clayfs mount [NAME]                               Laufwerk im Finder aktivieren
              clayfs unmount [NAME]                             Laufwerk sicher deaktivieren
              clayfs status                                     Registrierte Laufwerke und Status auflisten
              clayfs snapshot [NAME] [-m MSG]                   Sofortigen Schnappschuss erstellen
              clayfs timeline [NAME]                            Schnappschuss-Verlauf anzeigen
              clayfs diff [NAME] [SNAPSHOT_ID]                  Dateiänderungen anzeigen
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        Auf bestimmten Schnappschuss wiederherstellen
              clayfs compact [NAME]                             Ungenutzten Speicherplatz freigeben
              clayfs prune [NAME] [--keep N] [--days N]         Alte Schnappschüsse bereinigen
              clayfs autostart [on|off]                         Automatischen Start bei Anmeldung konfigurieren
              clayfs automount [NAME] [on|off]                  Automatisches Aktivieren beim Start konfigurieren
              clayfs watch [NAME]                               Automatische Hintergrundüberwachung
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       Mehrsprachige Hilfe anzeigen
            """)
        case .korean:
            print("""
            clayfs - 차세대 APFS 가상 드라이브 및 즉각적인 타임머신 (v\(version))

            사용법:
              clayfs create <NAME> [--size SIZE] [--path PATH]  새 가상 드라이브 생성
              clayfs mount [NAME]                               Finder에 드라이브 마운트
              clayfs unmount [NAME]                             안전하게 드라이브 마운트 해제
              clayfs status                                     등록된 드라이브 및 마운트 상태 목록
              clayfs snapshot [NAME] [-m MSG]                   즉시 스냅샷 생성
              clayfs timeline [NAME]                            스냅샷 기록 타임라인 표시
              clayfs diff [NAME] [SNAPSHOT_ID]                  파일 변경 차이 표시
              clayfs restore [NAME] <SNAPSHOT_ID> [PATH]        특정 스냅샷 상태로 복원
              clayfs compact [NAME]                             미사용 디스크 공간 회수
              clayfs prune [NAME] [--keep N] [--days N]         오래된 스냅샷 기록 정리
              clayfs autostart [on|off]                         로그인 시 ClayFS 자동 실행 설정
              clayfs automount [NAME] [on|off]                  부팅 시 드라이브 자동 마운트 설정
              clayfs watch [NAME]                               백그라운드 자동 스냅샷 감시
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       다국어 도움말 표시
            """)
        case .english:
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
              clayfs prune [NAME] [--keep N] [--days N]         Prune old snapshot history
              clayfs autostart [on|off]                         Configure launch at login for ClayFS
              clayfs automount [NAME] [on|off]                  Configure auto-mount on launch for a drive
              clayfs watch [NAME]                               Run background auto-snapshot monitor
              clayfs help [--lang <en|ja|zh|es|fr|de|ko>]       Show help in multiple languages
            """)
        }
    }
}
