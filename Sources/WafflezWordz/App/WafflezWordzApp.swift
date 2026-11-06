import AppKit
import SwiftUI
import WafflezCore

@main
struct WafflezWordzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(state)
        } label: {
            Image(systemName: state.isPaused || !state.settings.everywhereEnabled ? "square.grid.3x3" : "square.grid.3x3.fill")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { StudioWindow.shared.show(section: .settings) }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    let d = AppState.shared.newDocument()
                    StudioWindow.shared.open(document: d.id)
                }
                .keyboardShortcut("n")
            }
        }
    }
}

/// The menu under the waffle icon in the menu bar.
struct MenuBarMenu: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var everywhere = EverywhereController.shared

    var frontApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            ?? NSWorkspace.shared.frontmostApplication
    }

    var body: some View {
        Text(statusText)
        Divider()
        Button("Open Wafflez Studio") { StudioWindow.shared.show(section: .documents) }.keyboardShortcut("o")
        Button("Check Selected Text (\(state.settings.hotKey(.quickCheck).display))") { everywhere.quickCheck.run() }
        Button("Write with AI (\(state.settings.hotKey(.compose).display))") { everywhere.openCompose(reply: false) }
        Button("Open Side Panel (\(state.settings.hotKey(.sidePanel).display))") { everywhere.sideTab.open(tab: .suggestions) }
        Divider()
        if state.isPaused {
            Button("Resume Wafflez") { state.resume() }
        } else {
            Button("Turn Off Wafflez for 1 Hour") { state.pause(for: 3600) }
            Button("Turn Off Wafflez") { state.pause(for: nil) }
        }
        if let app = everywhere.bundleID.flatMap({ id in NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id } }) ?? frontApp,
           let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            Button(state.isBlocked(id) ? "Turn On in \(app.localizedName ?? "This App")" : "Turn Off in \(app.localizedName ?? "This App")") {
                state.toggleBlock(id)
            }
        }
        Toggle("Show Wafflez Tab", isOn: $state.settings.sideTabEnabled)
        Divider()
        if !state.accessibilityTrusted {
            Button("Grant Accessibility Permission…") { AX.requestTrust(); AX.openAccessibilitySettings() }
        }
        Button("Settings…") { StudioWindow.shared.show(section: .settings) }
        Button("Block List…") { StudioWindow.shared.show(section: .settings) }
        Divider()
        Button("Quit Wafflez Wordz") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private var statusText: String {
        if !state.accessibilityTrusted { return "⚠️ Needs Accessibility permission" }
        if let until = state.settings.pausedUntil, until > Date() {
            if until == .distantFuture { return "Wafflez is off" }
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        return state.settings.everywhereEnabled ? "Wafflez is on" : "Off in other apps"
    }
}
