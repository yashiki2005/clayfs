import SwiftUI
import ClayFSCore

public struct ClayFSMenuView: View {
    @ObservedObject var appState: ClayFSAppState
    @State private var snapshotMessage: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var newDriveName: String = "ClayDrive"
    @State private var newDriveSize: String = "50g"

    public init(appState: ClayFSAppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundColor(appState.isMounted ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    if let drive = appState.selectedDrive {
                        if appState.drives.count > 1 {
                            Menu {
                                ForEach(appState.drives) { d in
                                    Button(action: { appState.selectDrive(d) }) {
                                        HStack {
                                            Text(d.name)
                                            if d.name == drive.name {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(drive.name)
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .menuStyle(.borderlessButton)
                        } else {
                            Text(drive.name)
                                .font(.headline)
                        }
                        Text(appState.isMounted ? "マウント中 (保護有効)" : "未マウント")
                            .font(.caption)
                            .foregroundColor(appState.isMounted ? .green : .secondary)
                    } else {
                        Text("ClayFS")
                            .font(.headline)
                        Text("ドライブ未登録")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if appState.isMounted {
                    Button(action: { appState.openInFinder() }) {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help("Finder で開く")

                    Button("解除") {
                        appState.unmountSelectedDrive()
                    }
                    .buttonStyle(.bordered)
                } else if appState.selectedDrive != nil {
                    Button("マウント") {
                        appState.mountSelectedDrive()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal)
            }

            if appState.isMounted {
                // Quick Snapshot Input
                HStack {
                    TextField("スナップショットのメモ...", text: $snapshotMessage)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            takeSnapshot()
                        }

                    Button("保存") {
                        takeSnapshot()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(snapshotMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)

                // Snapshots Timeline
                VStack(alignment: .leading, spacing: 6) {
                    Text("タイムライン (履歴)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    if appState.snapshots.isEmpty {
                        Text("まだスナップショットはありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(appState.snapshots) { snap in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(snap.message)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            Text("\(formatDate(snap.timestamp)) • \(snap.id)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Button("復元") {
                                            appState.restore(snapshotID: snap.id)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 220)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("ドライブをマウントすると、\nファイル変更の自動保護と履歴が表示されます。")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }

            Divider()

            // Footer
            HStack {
                Button("+ 新規ドライブ") {
                    showCreateSheet = true
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("終了") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .frame(width: 320)
        .sheet(isPresented: $showCreateSheet) {
            VStack(spacing: 12) {
                Text("新しい ClayFS 仮想ドライブ")
                    .font(.headline)

                TextField("ドライブ名 (例: Projects)", text: $newDriveName)
                    .textFieldStyle(.roundedBorder)

                TextField("上限容量 (例: 50g, 100g)", text: $newDriveSize)
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
                }
            }
            .padding(20)
            .frame(width: 280)
        }
    }

    private func takeSnapshot() {
        let msg = snapshotMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        appState.takeSnapshot(message: msg)
        snapshotMessage = ""
    }

    private func createDrive() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleURL = home.appendingPathComponent("\(newDriveName).dmg.sparsebundle")
        do {
            let drive = try StorageManager.shared.createDrive(name: newDriveName, size: newDriveSize, bundleURL: bundleURL)
            appState.refreshDrives()
            appState.selectDrive(drive)
            appState.mountSelectedDrive()
        } catch {
            appState.statusMessage = "作成エラー: \(error.localizedDescription)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df.string(from: date)
    }
}
