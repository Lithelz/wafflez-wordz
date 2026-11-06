import AppKit
import SwiftUI
import WafflezCore

/// The thin Wafflez tab on the right edge of the screen, and the panel it opens (suggestions, chat, tone, write).
@MainActor
final class SideTabController {
    enum Tab: String, CaseIterable, Identifiable {
        case suggestions = "Suggestions", chat = "Chat", tone = "Tone", write = "Write"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .suggestions: return "checklist"
            case .chat: return "bubble.left.and.text.bubble.right"
            case .tone: return "face.smiling"
            case .write: return "lightbulb"
            }
        }
    }

    private let handle = PanelHost<SideHandleView>(allowsKey: false, level: .floating)
    private let panel = PanelHost<SidePanelView>(allowsKey: true, level: .floating)
    private var monitor: Any?
    private var hideWork: DispatchWorkItem?
    let model = SidePanelModel()
    let chat = ChatSession()

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        panel.anchorTop = true
    }

    func refresh() { model.objectWillChange.send() }

    private var handleY: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "wz.sidetab.y")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "wz.sidetab.y") }
    }

    private func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }

    private func mouseMoved() {
        let state = AppState.shared
        guard state.settings.sideTabEnabled, state.settings.everywhereEnabled, !state.isPaused, !panel.isVisible,
              let screen = screenUnderMouse() else { return }
        let p = NSEvent.mouseLocation
        let edge = screen.frame.maxX
        if p.x >= edge - 2 {
            hideWork?.cancel()
            if !handle.isVisible {
                var y = handleY
                if y <= screen.visibleFrame.minY || y >= screen.visibleFrame.maxY { y = screen.visibleFrame.midY + 60 }
                handle.show(SideHandleView(onOpen: { [weak self] in self?.open(tab: .suggestions) },
                                           onDragged: { [weak self] dy in self?.moveHandle(by: dy) }),
                            at: NSPoint(x: edge - 34, y: y))
            }
        } else if handle.isVisible && !handle.panel.frame.insetBy(dx: -30, dy: -20).contains(p) {
            guard hideWork == nil || hideWork!.isCancelled else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.handle.hide()
                    self?.hideWork = nil
                }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    private func moveHandle(by dy: CGFloat) {
        var f = handle.panel.frame
        f.origin.y -= dy
        handle.panel.setFrameOrigin(f.origin)
        handleY = f.maxY
    }

    func open(tab: Tab) {
        handle.hide()
        model.tab = tab
        guard let screen = screenUnderMouse() ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        panel.show(SidePanelView(model: model, chat: chat, close: { [weak self] in self?.close() }),
                   at: NSPoint(x: v.maxX - 412, y: v.maxY - 12), key: true)
    }

    func toggle() {
        if panel.isVisible { close() } else { open(tab: model.tab) }
    }

    func close() { panel.hide() }
}

final class SidePanelModel: ObservableObject {
    @Published var tab: SideTabController.Tab = .suggestions
}

struct SideHandleView: View {
    var onOpen: () -> Void
    var onDragged: (CGFloat) -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 6) {
                WaffleMark(size: 20)
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 32, height: 74)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(Theme.surface)
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Open Wafflez")
        .gesture(DragGesture(minimumDistance: 4).onEnded { onDragged($0.translation.height) })
    }
}

struct SidePanelView: View {
    @ObservedObject var model: SidePanelModel
    @ObservedObject var chat: ChatSession
    @ObservedObject var everywhere = EverywhereController.shared
    @ObservedObject var state = AppState.shared
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                WaffleMark(size: 22)
                Text("Wafflez Wordz").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                if !everywhere.appName.isEmpty {
                    Text("· \(everywhere.appName)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer()
                Button { StudioWindow.shared.show() } label: { Image(systemName: "macwindow") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary).help("Open Wafflez Studio")
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            Picker("", selection: $model.tab) {
                ForEach(SideTabController.Tab.allCases) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider().overlay(Theme.stroke)
            Group {
                switch model.tab {
                case .suggestions: suggestions
                case .chat:
                    ChatView(session: chat,
                             contextProvider: { (EverywhereController.shared.screenText, EverywhereController.shared.appName.isEmpty ? "screen" : EverywhereController.shared.appName) },
                             attachTargets: { SidePanelView.windowTargets() },
                             insertAction: { text in
                                 Task { @MainActor in _ = await TextInjector.insert(text, in: EverywhereController.shared.element) }
                             },
                             compact: true)
                case .tone: tone
                case .write: write
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 620)
        .panelChrome(radius: 16)
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !state.accessibilityTrusted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wafflez needs Accessibility permission to check text in other apps.").font(.system(size: 12.5)).foregroundStyle(Theme.text)
                        Button("Open System Settings") { AX.requestTrust(); AX.openAccessibilitySettings() }.buttonStyle(PrimaryButtonStyle())
                    }.card()
                } else if everywhere.element == nil {
                    Text("Click into any text box to see suggestions here. In Google Docs, select text and press \(state.settings.hotKey(.quickCheck).display).")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).card()
                } else {
                    HStack(spacing: 14) {
                        ScoreRing(score: everywhere.score, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(everywhere.suggestions.count) suggestion\(everywhere.suggestions.count == 1 ? "" : "s")").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                            HStack(spacing: 8) {
                                ForEach(IssueCategory.allCases) { c in
                                    let n = everywhere.suggestions.filter { $0.category == c }.count
                                    if n > 0 { HStack(spacing: 3) { CategoryDot(category: c, size: 7); Text("\(n)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary) } }
                                }
                            }
                        }
                    }
                    ForEach(everywhere.suggestions) { s in
                        SuggestionRow(suggestion: s,
                                      onSelect: { everywhere.showCard(s) },
                                      onAccept: s.replacements.isEmpty ? nil : { everywhere.acceptFromList(s) },
                                      onDismiss: { everywhere.dismiss(s) })
                    }
                }
            }
            .padding(12)
        }
    }

    private var tone: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let toneError { ErrorBanner(message: toneError) }
                if let t = everywhere.tone {
                    ToneDetailView(tone: t).card()
                } else {
                    Text("Write at least \(ToneDetector.minimumCharacters) characters in a text box to see how your writing may sound.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).card()
                }
                if !everywhere.currentFieldText.isEmpty {
                    Text("Adjust the tone with AI").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 6) {
                        ForEach([RewriteMode.confident, .friendly, .professional, .formal, .casual], id: \.self) { m in
                            Button(m.displayName) { rewriteField(m) }.buttonStyle(ChipButtonStyle())
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @State private var toneError: String?

    private func rewriteField(_ mode: RewriteMode) {
        guard let el = everywhere.element else { return }
        let original = everywhere.currentFieldText
        let s = state.settings
        Task { @MainActor in
            do {
                let out = try await state.ai().rewrite(original, mode: mode, goals: s.goals, dialect: s.dialect, brand: s.activeBrandTone)
                _ = await TextInjector.replace(range: NSRange(location: 0, length: (original as NSString).length), expected: original, with: out, in: el)
            } catch {
                toneError = error.localizedDescription
            }
        }
    }

    private var write: some View {
        ScrollView {
            ComposeView(screenContext: { EverywhereController.shared.screenText },
                        insert: { text in Task { @MainActor in _ = await TextInjector.insert(text, in: EverywhereController.shared.element) } },
                        close: close)
                .padding(10)
        }
    }

    /// Open windows in other apps that can be attached as chat context.
    static func windowTargets() -> [(String, () -> String)] {
        var out: [(String, () -> String)] = []
        let mine = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != mine {
            for win in AX.windows(pid: app.processIdentifier).prefix(4) {
                let title = AX.title(win) ?? ""
                guard !title.isEmpty else { continue }
                let label = "\(app.localizedName ?? "App") — \(title.prefix(40))"
                out.append((label, { AX.text(in: win, limit: 20000) }))
            }
        }
        return out
    }
}
