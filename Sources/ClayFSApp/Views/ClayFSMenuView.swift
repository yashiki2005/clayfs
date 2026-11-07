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
        ZStack {
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

            // Save Progress Overlay (Clockwise Clock)
            if appState.isSavingSnapshot {
                saveProgressOverlay
            }

            // Restore Modal Progress Overlay (Counter-Clockwise Clock)
            if appState.isRestoring {
                restoreProgressOverlay
            }
        }
        .frame(width: 540, height: 460)
        .sheet(isPresented: $showCreateSheet) {
            createDriveSheet
        }
        .sheet(item: $appState.pendingRestoreSnapshot) { snap in
            confirmRestoreSheet(snapshot: snap)
        }
        .sheet(isPresented: $appState.showRetentionSheet) {
            retentionPolicySheet
        }
        .sheet(isPresented: $appState.showStartupSheet) {
            startupSettingsSheet
        }
    }

    // MARK: - Left Sidebar

    @State private var hoveredDriveName: String?

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Header
            HStack {
                Text(L10n.virtualDrives)
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
                    Text(L10n.noDrivesRegistered)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.drives) { drive in
                            let isSelected = drive.name == appState.selectedDrive?.name
                            let isHovered = drive.name == hoveredDriveName
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

                                        Text(drive.isMounted ? L10n.mounted : L10n.unmounted)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.1) : Color(NSColor.textColor).opacity(0.001)))
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredDriveName = hovering ? drive.name : nil
                            }
                            .contextMenu {
                                if drive.isMounted {
                                    Button(L10n.openInFinder) {
                                        appState.selectDrive(drive)
                                        appState.openInFinder()
                                    }
                                    Button(L10n.unmount) {
                                        appState.selectDrive(drive)
                                        appState.unmountSelectedDrive()
                                    }
                                } else {
                                    Button(L10n.mount) {
                                        appState.selectDrive(drive)
                                        appState.mountSelectedDrive()
                                    }
                                }
                                Button(L10n.compact) {
                                    appState.selectDrive(drive)
                                    appState.compactSelectedDrive()
                                }
                                Button(L10n.retentionPolicyMenu) {
                                    appState.selectDrive(drive)
                                    appState.showRetentionSheet = true
                                }
                                Button(action: {
                                    appState.toggleAutoMount(for: drive)
                                }) {
                                    HStack {
                                        Text(L10n.autoMountOnLaunch)
                                        if drive.autoMount {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(L10n.removeFromList, role: .destructive) {
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
                    Text(L10n.newDrive)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
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

                            Text(drive.isMounted ? L10n.mounted : L10n.stopped)
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
                        .help(L10n.openInFinder)

                        Button(L10n.eject) {
                            appState.unmountSelectedDrive()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(L10n.mount) {
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
                            Text(L10n.storageUsage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(L10n.storageSummary(used: formatBytes(usedBytes), total: formatBytes(drive.totalBytes), free: formatBytes(drive.freeBytes)))
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
                        TextField(L10n.snapshotMemoPlaceholder, text: $snapshotMessage)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit {
                                takeSnapshot()
                            }

                        Button(L10n.save) {
                            takeSnapshot()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(snapshotMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12)

                    // Timeline
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(L10n.timelineHistory)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Button(action: { appState.showRetentionSheet = true }) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.retentionPolicyTitle)

                            Spacer()
                            Text(L10n.itemCount(appState.snapshots.count))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)

                        if appState.snapshots.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text(L10n.emptyTimelineMessage)
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

                                            Button(L10n.restore) {
                                                appState.pendingRestoreSnapshot = snap
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
                        Text(L10n.unmountedNotice)
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
                    Text(L10n.noDriveSelectedNotice)
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
        HStack(spacing: 8) {
            Button(action: { appState.showStartupSheet = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.startupSettings)

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

            Button(L10n.quit) {
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
            Text(L10n.createDriveTitle)
                .font(.headline)

            TextField(L10n.driveNamePlaceholder, text: $newDriveName)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.driveSizePlaceholder, text: $newDriveSize)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.drivePathPlaceholder, text: $newDrivePath)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(L10n.cancel) {
                    showCreateSheet = false
                }
                Spacer()
                Button(L10n.create) {
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

    // MARK: - Retention Policy Sheet

    @State private var retentionMaxCount: Int = 50
    @State private var retentionMaxDays: Int = 30
    @State private var isUnlimitedCount: Bool = false
    @State private var isUnlimitedDays: Bool = false

    private var retentionPolicySheet: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(L10n.retentionPolicyTitle)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Max Snapshots Count
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.maxSnapshotsLabel)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack {
                        Toggle(L10n.unlimited, isOn: $isUnlimitedCount)
                            .toggleStyle(.checkbox)
                        Spacer()
                        if !isUnlimitedCount {
                            Picker("", selection: $retentionMaxCount) {
                                Text(L10n.snapshotsFormat(10)).tag(10)
                                Text(L10n.snapshotsFormat(25)).tag(25)
                                Text(L10n.snapshotsFormat(50)).tag(50)
                                Text(L10n.snapshotsFormat(100)).tag(100)
                                Text(L10n.snapshotsFormat(200)).tag(200)
                            }
                            .frame(width: 140)
                        }
                    }
                }

                Divider()

                // Max Age Days
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.maxDaysLabel)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack {
                        Toggle(L10n.unlimited, isOn: $isUnlimitedDays)
                            .toggleStyle(.checkbox)
                        Spacer()
                        if !isUnlimitedDays {
                            Picker("", selection: $retentionMaxDays) {
                                Text(L10n.daysFormat(3)).tag(3)
                                Text(L10n.daysFormat(7)).tag(7)
                                Text(L10n.daysFormat(14)).tag(14)
                                Text(L10n.daysFormat(30)).tag(30)
                                Text(L10n.daysFormat(90)).tag(90)
                                Text(L10n.daysFormat(180)).tag(180)
                            }
                            .frame(width: 140)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            HStack {
                Button(L10n.cancel) {
                    appState.showRetentionSheet = false
                }
                Spacer()
                Button(L10n.saveSettings) {
                    let count = isUnlimitedCount ? nil : retentionMaxCount
                    let days = isUnlimitedDays ? nil : retentionMaxDays
                    appState.updateRetentionPolicy(maxSnapshots: count, maxAgeDays: days)
                    appState.showRetentionSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            if let policy = appState.selectedDrive?.retentionPolicy {
                if let count = policy.maxSnapshots {
                    isUnlimitedCount = false
                    retentionMaxCount = count
                } else {
                    isUnlimitedCount = true
                }
                if let days = policy.maxAgeDays {
                    isUnlimitedDays = false
                    retentionMaxDays = days
                } else {
                    isUnlimitedDays = true
                }
            }
        }
    }

    // MARK: - Startup Settings Sheet

    private var startupSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.startupSettings)
                    .font(.headline)
                Spacer()
                Button(action: { appState.showStartupSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.launchAtLogin, isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)

                Divider()

                Text(L10n.autoMountOnLaunch)
                    .font(.subheadline.bold())

                if appState.drives.isEmpty {
                    Text(L10n.noDrivesRegistered)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(appState.drives) { drive in
                            HStack {
                                Image(systemName: "externaldrive")
                                    .foregroundColor(.accentColor)
                                Text(drive.name)
                                    .font(.caption)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { drive.autoMount },
                                    set: { _ in appState.toggleAutoMount(for: drive) }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            HStack {
                Spacer()
                Button(L10n.close) {
                    appState.showStartupSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 340)
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
            appState.statusMessage = L10n.createError(error.localizedDescription)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Restore Confirmation & Progress

    private func confirmRestoreSheet(snapshot: Snapshot) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text(L10n.restoreConfirmTitle)
                    .font(.headline)

                Text("「\(snapshot.message)」\n(\(snapshot.id))")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                Text(L10n.restoreConfirmExplanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Button(L10n.cancel) {
                    appState.pendingRestoreSnapshot = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.executeRestoreButton) {
                    appState.executeRestore(snapshot: snapshot)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var saveProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 16) {
                if appState.saveSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.green)
                } else {
                    AnimatedClockView(isReverse: false)
                }

                VStack(spacing: 6) {
                    Text(appState.saveSuccess ? L10n.saveSuccessTitle : L10n.savingSnapshotTitle)
                        .font(.headline)

                    Text(appState.saveStage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(color: .black.opacity(0.2), radius: 15)
        }
    }

    private var restoreProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 16) {
                if appState.restoreSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.green)
                } else {
                    AnimatedClockView(isReverse: true)
                }

                VStack(spacing: 6) {
                    Text(appState.restoreSuccess ? L10n.restoreSuccessTitle : L10n.restoringTitle)
                        .font(.headline)

                    Text(appState.restoreStage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(color: .black.opacity(0.2), radius: 15)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Animated Clock (Clockwise for Save, Counter-Clockwise for Restore)

struct AnimatedClockView: View {
    let isReverse: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let speed: Double = 240.0 // degrees per second
            let minuteAngle = (elapsed * speed).truncatingRemainder(dividingBy: 360.0)
            let hourAngle = minuteAngle / 12.0

            let effectiveMin = isReverse ? -minuteAngle : minuteAngle
            let effectiveHour = isReverse ? -hourAngle : hourAngle

            ZStack {
                // Outer Dial Ring
                Circle()
                    .stroke(isReverse ? Color.orange : Color.accentColor, lineWidth: 3)
                    .frame(width: 52, height: 52)

                // 12 Hour tick marks
                ForEach(0..<12) { i in
                    Rectangle()
                        .fill((i % 3 == 0) ? (isReverse ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.4))
                        .frame(width: 2, height: (i % 3 == 0) ? 6 : 3)
                        .offset(y: -22)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                // Hour Hand (slower)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary)
                    .frame(width: 3, height: 14)
                    .offset(y: -7)
                    .rotationEffect(.degrees(effectiveHour))

                // Minute Hand (faster)
                RoundedRectangle(cornerRadius: 1)
                    .fill(isReverse ? Color.orange : Color.accentColor)
                    .frame(width: 2, height: 20)
                    .offset(y: -10)
                    .rotationEffect(.degrees(effectiveMin))

                // Center Pin
                Circle()
                    .fill(isReverse ? Color.orange : Color.accentColor)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 60, height: 60)
        }
    }
}
