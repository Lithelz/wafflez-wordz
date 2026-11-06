import AppKit
import WafflezCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            NSApp.setActivationPolicy(.accessory)
            // Launch arguments used by the CI smoke test: --section <name> opens that Studio screen, --no-welcome skips the intro.
            let args = CommandLine.arguments
            let section = args.firstIndex(of: "--section").flatMap { i in i + 1 < args.count ? StudioSection(rawValue: args[i + 1]) : nil }
            if args.contains("--no-welcome") { AppState.shared.settings.hasSeenWelcome = true }
            if !AX.isTrusted && section == nil { AX.requestTrust() }
            EverywhereController.shared.start()
            AppDelegate.registerHotKeys()
            if args.contains("--everywhere-test") {
                // Open a suggestion card, then the side panel, so CI screenshots show both.
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { EverywhereController.shared.openFirstCard() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                    EverywhereController.shared.hideCard()
                    EverywhereController.shared.sideTab.open(tab: .suggestions)
                }
                // CI check: report what Wafflez sees in the frontmost app.
                for delay in [6.0, 8.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        let e = EverywhereController.shared
                        let rules = e.suggestions.map(\.ruleID).joined(separator: ",")
                        print("EVERYWHERE trusted=\(AX.isTrusted) app=\(e.appName) attached=\(e.element != nil) suggestions=\(e.suggestions.count) [\(rules)] tone=\(e.tone?.summary ?? "-")")
                        fflush(stdout)
                    }
                }
            }
            // First launch: open the Studio so people see what Wafflez does.
            if let section {
                StudioWindow.shared.show(section: section)
            } else if !AppState.shared.settings.hasSeenWelcome {
                StudioWindow.shared.show(section: .documents)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { StudioWindow.shared.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.saveNow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    static func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        let s = AppState.shared.settings
        let everywhere = EverywhereController.shared
        for (index, action) in HotKeyAction.allCases.enumerated() {
            let id = UInt32(index + 1)
            center.register(id: id, key: s.hotKey(action)) {
                MainActor.assumeIsolated {
                    switch action {
                    case .quickCheck: everywhere.quickCheck.run()
                    case .compose: everywhere.openCompose(reply: false)
                    case .rewriteSelection: everywhere.openAssistantForSelection()
                    case .sidePanel: everywhere.sideTab.toggle()
                    case .snippets: everywhere.openSnippets()
                    case .pause:
                        let state = AppState.shared
                        if state.isPaused { state.resume() } else { state.pause(for: 3600) }
                    }
                }
            }
        }
    }
}
