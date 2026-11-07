import SwiftUI
import ClayFSCore
import Combine

@MainActor
public final class ClayFSAppState: ObservableObject {
    @Published public var drives: [VolumeInfo] = []
    @Published public var selectedDrive: VolumeInfo?
    @Published public var activeMountURL: URL?
    @Published public var snapshots: [Snapshot] = []
    @Published public var isMounted: Bool = false
    @Published public var isCreatingDrive: Bool = false
    @Published public var statusMessage: String?

    private var pollTimer: AnyCancellable?
    private var monitor: FSEventsMonitor?

    public init() {
        refreshDrives()
        startPolling()
    }

    public func refreshDrives() {
        let list = DriveRegistry.shared.loadDrives(cleanMissing: true)
        self.drives = list
        if selectedDrive == nil || !list.contains(where: { $0.name == selectedDrive?.name }) {
            if let mounted = list.first(where: { StorageManager.shared.findMountPoint(for: $0.bundleURL) != nil }) {
                self.selectedDrive = mounted
            } else {
                self.selectedDrive = list.first
            }
        }
        checkMountStatus()
    }

    public func selectDrive(_ drive: VolumeInfo) {
        self.selectedDrive = drive
        self.statusMessage = nil
        checkMountStatus()
    }

    public func removeDrive(_ drive: VolumeInfo) {
        try? DriveRegistry.shared.unregisterDrive(named: drive.name)
        refreshDrives()
    }

    public func checkMountStatus() {
        guard let drive = selectedDrive else {
            self.activeMountURL = nil
            self.isMounted = false
            self.snapshots = []
            return
        }

        if let mount = StorageManager.shared.findMountPoint(for: drive.bundleURL) {
            self.activeMountURL = mount
            self.isMounted = true
            loadSnapshots(mountURL: mount)
        } else {
            self.activeMountURL = nil
            self.isMounted = false
            self.snapshots = []
        }
    }

    public func loadSnapshots(mountURL: URL) {
        do {
            self.snapshots = try SnapshotManager.shared.listSnapshots(volumeMountURL: mountURL, limit: 30)
        } catch {
            self.snapshots = []
        }
    }

    public func mountSelectedDrive() {
        guard let drive = selectedDrive else { return }
        statusMessage = "マウント中..."
        Task {
            do {
                let info = try StorageManager.shared.mountDrive(bundleURL: drive.bundleURL, showInFinder: true)
                self.activeMountURL = info.mountURL
                self.isMounted = true
                self.statusMessage = nil
                if let m = info.mountURL {
                    loadSnapshots(mountURL: m)
                    startWatching(mountURL: m)
                }
            } catch {
                self.statusMessage = "マウント失敗: \(error.localizedDescription)"
            }
        }
    }

    public func unmountSelectedDrive() {
        guard let mountURL = activeMountURL else { return }
        stopWatching()
        statusMessage = "アンマウント中..."
        Task {
            do {
                try StorageManager.shared.unmountDrive(mountURL: mountURL)
                self.activeMountURL = nil
                self.isMounted = false
                self.snapshots = []
                self.statusMessage = nil
            } catch {
                self.statusMessage = "アンマウント失敗: \(error.localizedDescription)"
            }
        }
    }

    public func takeSnapshot(message: String) {
        guard let mountURL = activeMountURL else { return }
        statusMessage = "スナップショット作成中..."
        Task {
            do {
                let snap = try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: message)
                loadSnapshots(mountURL: mountURL)
                self.statusMessage = "保存完了: [\(snap.id)]"
            } catch {
                self.statusMessage = "スナップショット失敗: \(error.localizedDescription)"
            }
        }
    }

    public func restore(snapshotID: String) {
        guard let mountURL = activeMountURL else { return }
        statusMessage = "復元中..."
        Task {
            do {
                try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snapshotID)
                loadSnapshots(mountURL: mountURL)
                self.statusMessage = "復元完了"
            } catch {
                self.statusMessage = "復元失敗: \(error.localizedDescription)"
            }
        }
    }

    public func openInFinder() {
        guard let mountURL = activeMountURL else { return }
        let ws = mountURL.appendingPathComponent("Workspace")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ws.path)
    }

    private func startPolling() {
        pollTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkMountStatus()
            }
    }

    private func startWatching(mountURL: URL) {
        stopWatching()
        let ws = mountURL.appendingPathComponent("Workspace")
        monitor = FSEventsMonitor(watchURL: ws, debounceSeconds: 5.0) { [weak self] in
            Task { @MainActor in
                guard let self = self, let m = self.activeMountURL else { return }
                do {
                    let diffs = try SnapshotManager.shared.diff(volumeMountURL: m)
                    if !diffs.isEmpty {
                        _ = try SnapshotManager.shared.createSnapshot(
                            volumeMountURL: m,
                            message: "自動保存 (\(diffs.count)件の変更)"
                        )
                        self.loadSnapshots(mountURL: m)
                    }
                } catch {}
            }
        }
        monitor?.start()
    }

    private func stopWatching() {
        monitor?.stop()
        monitor = nil
    }
}
