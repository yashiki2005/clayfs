import Foundation

public enum L10n {
    public static var isJapanese: Bool {
        // 1. Check environment variables (for testing or CLI launches)
        let env = ProcessInfo.processInfo.environment
        let envLang = env["LC_ALL"] ?? env["LC_MESSAGES"] ?? env["LANG"] ?? ""
        let lowerEnv = envLang.lowercased()
        if lowerEnv.starts(with: "ja") { return true }
        if lowerEnv.starts(with: "en") || envLang == "C" || envLang == "POSIX" { return false }

        // 2. System Preferred Languages (macOS Language & Region setting)
        if let preferred = Locale.preferredLanguages.first?.lowercased() {
            if preferred.starts(with: "ja") { return true }
            if preferred.starts(with: "en") { return false }
        }

        // 3. Current locale fallback
        if let langCode = Locale.current.language.languageCode?.identifier.lowercased() {
            if langCode.starts(with: "ja") { return true }
        }

        return false
    }

    // MARK: - Sidebar & Drive List
    public static var virtualDrives: String { isJapanese ? "仮想ドライブ" : "Virtual Drives" }
    public static var noDrivesRegistered: String { isJapanese ? "ドライブ未登録" : "No Drives Registered" }
    public static var mounted: String { isJapanese ? "マウント中" : "Mounted" }
    public static var unmounted: String { isJapanese ? "未マウント" : "Unmounted" }
    public static var stopped: String { isJapanese ? "停止中" : "Stopped" }
    public static var openInFinder: String { isJapanese ? "Finder で開く" : "Open in Finder" }
    public static var unmount: String { isJapanese ? "アンマウント" : "Unmount" }
    public static var mount: String { isJapanese ? "マウント" : "Mount" }
    public static var eject: String { isJapanese ? "解除" : "Eject" }
    public static var removeFromList: String { isJapanese ? "リストから削除" : "Remove from List" }
    public static var newDrive: String { isJapanese ? "新規ドライブ" : "New Drive" }

    // MARK: - Detail View & Storage
    public static var storageUsage: String { isJapanese ? "ストレージ使用量" : "Storage Usage" }
    public static func freeSpace(_ free: String) -> String {
        isJapanese ? "空き \(free)" : "Free \(free)"
    }
    public static func storageSummary(used: String, total: String, free: String) -> String {
        "\(used) / \(total) (\(freeSpace(free)))"
    }

    // MARK: - Snapshot & Timeline
    public static var snapshotMemoPlaceholder: String { isJapanese ? "スナップショットのメモ..." : "Snapshot memo..." }
    public static var save: String { isJapanese ? "保存" : "Save" }
    public static var timelineHistory: String { isJapanese ? "タイムライン (履歴)" : "Timeline (History)" }
    public static func itemCount(_ count: Int) -> String {
        if isJapanese {
            return "\(count) 件"
        } else {
            return count == 1 ? "1 item" : "\(count) items"
        }
    }
    public static var emptyTimelineMessage: String {
        isJapanese
            ? "履歴はまだありません。保存するかファイルを編集すると自動作成されます。"
            : "No snapshots yet. Take a snapshot or edit files to record history automatically."
    }
    public static var restore: String { isJapanese ? "復元" : "Restore" }

    // MARK: - Empty States
    public static var unmountedNotice: String {
        isJapanese
            ? "このドライブは現在マウントされていません。\n「マウント」を押すと Finder に現れ、作業を開始できます。"
            : "This drive is currently unmounted.\nClick 'Mount' to mount it in Finder and start working."
    }
    public static var noDriveSelectedNotice: String {
        isJapanese
            ? "左のリストからドライブを選択するか、\n「新規ドライブ」を作成してください。"
            : "Select a drive from the sidebar,\nor click 'New Drive' to create one."
    }

    // MARK: - Footer
    public static var quit: String { isJapanese ? "終了" : "Quit" }

    // MARK: - Create Drive Sheet
    public static var createDriveTitle: String { isJapanese ? "新しい ClayFS 仮想ドライブ" : "New ClayFS Virtual Drive" }
    public static var driveNamePlaceholder: String { isJapanese ? "ドライブ名 (例: Projects)" : "Drive Name (e.g. Projects)" }
    public static var driveSizePlaceholder: String { isJapanese ? "上限容量 (例: 50g, 100g)" : "Max Capacity (e.g. 50g, 100g)" }
    public static var drivePathPlaceholder: String { isJapanese ? "保存先パス (空欄でホームディレクトリ)" : "Storage Path (leave blank for home dir)" }
    public static var cancel: String { isJapanese ? "キャンセル" : "Cancel" }
    public static var create: String { isJapanese ? "作成" : "Create" }
    public static func createError(_ msg: String) -> String {
        isJapanese ? "作成エラー: \(msg)" : "Creation Error: \(msg)"
    }

    // MARK: - Restore Confirmation Sheet
    public static var restoreConfirmTitle: String { isJapanese ? "スナップショットを復元" : "Restore Snapshot" }
    public static var restoreConfirmExplanation: String {
        isJapanese
            ? "現在の作業フォルダの内容をこの状態に復元します。\n※復元直前の現在の状態も安全スナップショットとして自動保存されるため、いつでもやり直せます。"
            : "Restores the workspace directory to this snapshot state.\n* Current workspace is automatically saved as a safety snapshot before restoring, so you can always roll back."
    }
    public static var executeRestoreButton: String { isJapanese ? "復元を実行" : "Execute Restore" }

    // MARK: - Save Modal Overlay
    public static var savingSnapshotTitle: String { isJapanese ? "スナップショットを保存中..." : "Saving Snapshot..." }
    public static var saveSuccessTitle: String { isJapanese ? "スナップショット保存完了" : "Snapshot Saved" }
    public static var recordingCowStage: String { isJapanese ? "APFS CoW で現在の状態を記録中..." : "Recording workspace state with APFS CoW..." }
    public static func saveDoneStage(_ id: String) -> String {
        isJapanese ? "保存完了: [\(id)]" : "Saved: [\(id)]"
    }
    public static func saveFailed(_ err: String) -> String {
        isJapanese ? "スナップショット失敗: \(err)" : "Snapshot failed: \(err)"
    }

    // MARK: - Restore Modal Overlay
    public static var restoringTitle: String { isJapanese ? "過去の状態に復元中 (タイムトラベル)..." : "Restoring Snapshot (Time Travel)..." }
    public static var restoreSuccessTitle: String { isJapanese ? "復元完了" : "Restore Completed" }
    public static var restoringStage: String { isJapanese ? "過去のスナップショットを展開中 (タイムトラベル)..." : "Unpacking snapshot state (Time Travel)..." }
    public static func restoreDoneStage(_ id: String) -> String {
        isJapanese ? "[\(id)] の状態に復元完了！" : "Successfully restored to [\(id)]!"
    }
    public static func restoredMessage(_ id: String) -> String {
        isJapanese ? "[\(id)] へ復元完了" : "Restored to [\(id)]"
    }
    public static func restoreFailed(_ err: String) -> String {
        isJapanese ? "復元失敗: \(err)" : "Restore failed: \(err)"
    }

    // MARK: - Status Messages
    public static var mounting: String { isJapanese ? "マウント中..." : "Mounting..." }
    public static func mountFailed(_ err: String) -> String {
        isJapanese ? "マウント失敗: \(err)" : "Mount failed: \(err)"
    }
    public static var unmounting: String { isJapanese ? "アンマウント中..." : "Unmounting..." }
    public static func unmountFailed(_ err: String) -> String {
        isJapanese ? "アンマウント失敗: \(err)" : "Unmount failed: \(err)"
    }
    public static func autoSaveMessage(_ count: Int) -> String {
        isJapanese ? "自動保存 (\(count)件の変更)" : "Auto-save (\(count) changes)"
    }
}
