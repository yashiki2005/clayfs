import SwiftUI
import ClayFSCore

public struct ClayFSMenuView: View {
    @ObservedObject var appState: ClayFSAppState
    @State private var snapshotMessage: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var newDriveName: String = ""
    @State private var newDriveSize: String = "50g"
    @State private var newDrivePath: String = ""

    public init(appState: ClayFSAppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Two-Column View
            HStack(spacing: 0) {
                // Left Column: Drive Sidebar
                sidebarView
                    .frame(width: 180)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

                Divider()

                // Right Column: Detail & Timeline View
                detailView
                    .frame(width: 360)
            }
            .frame(height: 420)

            Divider()

            // Global Footer Bar
            footerView
                .frame(height: 38)
                .padding(.horizontal, 12)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 460)
        .sheet(isPresented: $showCreateSheet) {
            createDriveSheet
        }
    }

    // MARK: - Left Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Header
            HStack {
                Text("仮想ドライブ")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(appState.drives.count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Drives List
            if appState.drives.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("ドライブ未登録")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.drives) { drive in
                            let isSelected = drive.name == appState.selectedDrive?.name
                            Button(action: {
                                appState.selectDrive(drive)
                            }) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(drive.isMounted ? Color.green : Color.gray.opacity(0.5))
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(drive.name)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Text(drive.isMounted ? "マウント中" : "未マウント")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if drive.isMounted {
                                    Button("Finder で開く") {
                                        appState.selectDrive(drive)
                                        appState.openInFinder()
                                    }
                                    Button("アンマウント") {
                                        appState.selectDrive(drive)
                                        appState.unmountSelectedDrive()
                                    }
                                } else {
                                    Button("マウント") {
                                        appState.selectDrive(drive)
                                        appState.mountSelectedDrive()
                                    }
                                }
                                Divider()
                                Button("リストから削除", role: .destructive) {
                                    appState.removeDrive(drive)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }

            Divider()

            // Add Drive Button
            Button(action: { showCreateSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("新規ドライブ")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Right Detail & Timeline

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let drive = appState.selectedDrive {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(drive.name)
                                .font(.title3.bold())

                            Text(drive.isMounted ? "マウント中" : "停止中")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(drive.isMounted ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
                                .foregroundColor(drive.isMounted ? .green : .secondary)
                                .cornerRadius(4)
                        }

                        Text(drive.bundleURL.path)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if drive.isMounted {
                        Button(action: { appState.openInFinder() }) {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .help("Finder で開く")

                        Button("解除") {
                            appState.unmountSelectedDrive()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("マウント") {
                            appState.mountSelectedDrive()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Storage Bar
                if drive.isMounted && drive.totalBytes > 0 {
                    let usedBytes = max(0, drive.totalBytes - drive.freeBytes)
                    let fraction = Double(usedBytes) / Double(drive.totalBytes)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("ストレージ使用量")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatBytes(usedBytes)) / \(formatBytes(drive.totalBytes)) (空き \(formatBytes(drive.freeBytes)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    }
                    .padding(.horizontal, 12)
                }

                Divider()

                if drive.isMounted {
                    // Quick Snapshot
                    HStack(spacing: 6) {
                        TextField("スナップショットのメモ...", text: $snapshotMessage)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit {
                                takeSnapshot()
                            }

                        Button("保存") {
                            takeSnapshot()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(snapshotMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12)

                    // Timeline
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("タイムライン (履歴)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(appState.snapshots.count) 件")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)

                        if appState.snapshots.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("履歴はまだありません。保存するかファイルを編集すると自動作成されます。")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 16)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(appState.snapshots) { snap in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(snap.message)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .lineLimit(1)
                                                Text("\(formatDate(snap.timestamp)) • \(snap.id)")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Button("復元") {
                                                appState.restore(snapshotID: snap.id)
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.wifi")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("このドライブは現在マウントされていません。\n「マウント」を押すと Finder に現れ、作業を開始できます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("左のリストからドライブを選択するか、\n「新規ドライブ」を作成してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            } else {
                Text("ClayFS v2.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Sheet

    private var createDriveSheet: some View {
        VStack(spacing: 12) {
            Text("新しい ClayFS 仮想ドライブ")
                .font(.headline)

            TextField("ドライブ名 (例: Projects)", text: $newDriveName)
                .textFieldStyle(.roundedBorder)

            TextField("上限容量 (例: 50g, 100g)", text: $newDriveSize)
                .textFieldStyle(.roundedBorder)

            TextField("保存先パス (空欄でホームディレクトリ)", text: $newDrivePath)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("キャンセル") {
                    showCreateSheet = false
                }
                Spacer()
                Button("作成") {
                    createDrive()
                    showCreateSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDriveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func takeSnapshot() {
        let msg = snapshotMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        appState.takeSnapshot(message: msg)
        snapshotMessage = ""
    }

    private func createDrive() {
        let name = newDriveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let bundleURL: URL
        let path = newDrivePath.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            bundleURL = URL(fileURLWithPath: expanded)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            bundleURL = home.appendingPathComponent("\(name).dmg.sparsebundle")
        }

        do {
            let drive = try StorageManager.shared.createDrive(name: name, size: newDriveSize, bundleURL: bundleURL)
            appState.refreshDrives()
            appState.selectDrive(drive)
            appState.mountSelectedDrive()
            newDriveName = ""
            newDrivePath = ""
        } catch {
            appState.statusMessage = "作成エラー: \(error.localizedDescription)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df.string(from: date)
    }
}
