import SwiftUI
import ClayFSCore

@main
struct ClayFSApp: App {
    @StateObject private var appState = ClayFSAppState()

    var body: some Scene {
        MenuBarExtra {
            ClayFSMenuView(appState: appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: appState.isMounted ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                if appState.isMounted {
                    Text("ClayFS")
                        .font(.caption2)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
