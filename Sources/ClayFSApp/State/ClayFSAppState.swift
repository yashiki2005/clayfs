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

    // Save state
    @Published public var isSavingSnapshot: Bool = false
    @Published public var saveStage: String = ""
    @Published public var saveSuccess: Bool = false

    // Restore state
    @Published public var isRestoring: Bool = false
    @Published public var restoreStage: String = ""
    @Published public var restoreSuccess: Bool = false
    @Published public var pendingRestoreSnapshot: Snapshot? = nil

    // Retention Policy sheet
    @Published public var showRetentionSheet: Bool = false

    private var pollTimer: AnyCancellable?
    private var monitor: FSEventsMonitor?

    public init() {
        refreshDrives()
        startPolling()
    }

    public func refreshDrives() {
        var list = DriveRegistry.shared.loadDrives(cleanMissing: true)
        for i in 0..<list.count {
            if let mount = StorageManager.shared.findMountPoint(for: list[i].bundleURL) {
                list[i].isMounted = true
                list[i].mountURL = mount
                if let values = try? mount.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]) {
                    list[i].freeBytes = Int64(values.volumeAvailableCapacity ?? 0)
                    list[i].totalBytes = Int64(values.volumeTotalCapacity ?? 0)
                }
            } else {
                list[i].isMounted = false
                list[i].mountURL = nil
            }
        }
        self.drives = list

        if selectedDrive == nil || !list.contains(where: { $0.name == selectedDrive?.name }) {
            if let mounted = list.first(where: { $0.isMounted }) {
                self.selectedDrive = mounted
            } else {
                self.selectedDrive = list.first
            }
        } else if let sel = selectedDrive, let updated = list.first(where: { $0.name == sel.name }) {
            self.selectedDrive = updated
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
        statusMessage = L10n.mounting
        Task {
            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try StorageManager.shared.mountDrive(bundleURL: drive.bundleURL, showInFinder: true)
                }.value

                await MainActor.run {
                    self.activeMountURL = info.mountURL
                    self.isMounted = true
                    self.statusMessage = nil
                    self.refreshDrives()
                    if let m = info.mountURL {
                        self.loadSnapshots(mountURL: m)
                        self.startWatching(mountURL: m)
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.mountFailed(error.localizedDescription)
                }
            }
        }
    }

    public func unmountSelectedDrive() {
        guard let mountURL = activeMountURL else { return }
        stopWatching()
        statusMessage = L10n.unmounting
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try StorageManager.shared.unmountDrive(mountURL: mountURL)
                }.value

                await MainActor.run {
                    self.activeMountURL = nil
                    self.isMounted = false
                    self.snapshots = []
                    self.statusMessage = nil
                    self.refreshDrives()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.unmountFailed(error.localizedDescription)
                }
            }
        }
    }

    public func compactSelectedDrive() {
        guard let drive = selectedDrive else { return }
        statusMessage = L10n.compacting
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try StorageManager.shared.compactDrive(bundleURL: drive.bundleURL)
                }.value

                await MainActor.run {
                    self.statusMessage = L10n.compactSuccess
                    self.refreshDrives()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.compactFailed(error.localizedDescription)
                }
            }
        }
    }

    public func takeSnapshot(message: String) {
        guard let mountURL = activeMountURL else { return }
        let policy = selectedDrive?.retentionPolicy ?? .default
        isSavingSnapshot = true
        saveSuccess = false
        saveStage = L10n.recordingCowStage

        Task {
            // Keep animation visible smoothly for at least 800ms
            async let minDelay: () = Task.sleep(nanoseconds: 800_000_000)

            do {
                let snap = try await Task.detached(priority: .userInitiated) {
                    try SnapshotManager.shared.createSnapshot(volumeMountURL: mountURL, message: message, policy: policy)
                }.value

                _ = try? await minDelay

                await MainActor.run {
                    self.loadSnapshots(mountURL: mountURL)
                    self.saveStage = L10n.saveDoneStage(snap.id)
                    self.saveSuccess = true
                    self.statusMessage = L10n.saveDoneStage(snap.id)
                }

                // Show success feedback before closing modal
                try? await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run {
                    self.isSavingSnapshot = false
                }
            } catch {
                await MainActor.run {
                    self.isSavingSnapshot = false
                    self.statusMessage = L10n.saveFailed(error.localizedDescription)
                }
            }
        }
    }

    public func updateRetentionPolicy(maxSnapshots: Int?, maxAgeDays: Int?) {
        guard let drive = selectedDrive else { return }
        let newPolicy = RetentionPolicy(maxSnapshots: maxSnapshots, maxAgeDays: maxAgeDays)
        var updated = drive
        updated.retentionPolicy = newPolicy
        self.selectedDrive = updated

        if let idx = drives.firstIndex(where: { $0.name == drive.name }) {
            drives[idx] = updated
        }

        try? DriveRegistry.shared.registerDrive(updated)

        // Run pruning immediately if mounted
        if let mount = activeMountURL {
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                let pruned = (try? SnapshotManager.shared.pruneSnapshots(volumeMountURL: mount, policy: newPolicy)) ?? []
                await MainActor.run {
                    self.loadSnapshots(mountURL: mount)
                    if !pruned.isEmpty {
                        self.statusMessage = L10n.prunedSnapshotsCount(pruned.count)
                    }
                }
            }
        }
    }

    public func executeRestore(snapshot: Snapshot) {
        guard let mountURL = activeMountURL else { return }
        isRestoring = true
        restoreSuccess = false
        restoreStage = L10n.restoringStage

        Task {
            // Keep reverse clock animation visible for at least 1000ms
            async let minDelay: () = Task.sleep(nanoseconds: 1_000_000_000)

            do {
                try await Task.detached(priority: .userInitiated) {
                    try SnapshotManager.shared.restore(volumeMountURL: mountURL, snapshotID: snapshot.id)
                }.value

                _ = try? await minDelay

                await MainActor.run {
                    self.loadSnapshots(mountURL: mountURL)
                    self.restoreStage = L10n.restoreDoneStage(snapshot.id)
                    self.restoreSuccess = true
                    self.statusMessage = L10n.restoredMessage(snapshot.id)
                }

                // Show success feedback before closing modal
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.isRestoring = false
                    self.pendingRestoreSnapshot = nil
                }
            } catch {
                await MainActor.run {
                    self.isRestoring = false
                    self.statusMessage = L10n.restoreFailed(error.localizedDescription)
                }
            }
        }
    }

    public func openInFinder() {
        guard let mountURL = activeMountURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountURL.path)
    }

    private func startPolling() {
        pollTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDrives()
            }
    }

    private func startWatching(mountURL: URL) {
        stopWatching()
        monitor = FSEventsMonitor(watchURL: mountURL, debounceSeconds: 5.0) { [weak self] in
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try SnapshotManager.shared.createSnapshot(
                        volumeMountURL: mountURL,
                        message: L10n.autoSaveMessage(1)
                    )
                    await MainActor.run {
                        self.loadSnapshots(mountURL: mountURL)
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
