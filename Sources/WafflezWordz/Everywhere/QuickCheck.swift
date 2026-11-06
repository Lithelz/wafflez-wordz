import AppKit
import SwiftUI
import WafflezCore

/// Universal mode for editors that hide their text from Accessibility (Google Docs, Figma, some Electron apps):
/// press the shortcut, Wafflez copies your selection, checks it in a window, and pastes the result back.
@MainActor
final class QuickCheckController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var editor: EditorController?
    private var sourceApp: NSRunningApplication?
    private var sourceElement: AXUIElement?
    private var sourceRange: NSRange?
    private var originalText = ""

    func run() {
        Task { @MainActor in
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier, window?.isVisible == true {
                window?.makeKeyAndOrderFront(nil)
                return
            }
            sourceApp = front
            sourceElement = nil
            sourceRange = nil
            var text = ""
            if AX.isTrusted, let focused = AX.focusedElement(), let sel = AX.selectedText(focused), !sel.trimmed.isEmpty {
                text = sel
                sourceElement = focused
                sourceRange = AX.selectedRange(focused)
            } else if let copied = await TextInjector.copySelection(), !copied.trimmed.isEmpty {
                text = copied
            }
            present(text)
        }
    }

    /// Selects everything in the source app, copies it and checks it.
    func selectAllAndCheck() {
        guard let app = sourceApp else { return }
        window?.orderOut(nil)
        Task { @MainActor in
            app.activate()
            try? await Task.sleep(nanoseconds: 250_000_000)
            await TextInjector.selectAll()
            let copied = await TextInjector.copySelection() ?? ""
            sourceElement = nil
            sourceRange = nil
            present(copied)
        }
    }

    private func present(_ text: String) {
        originalText = text
        let controller = EditorController(attributed: NSAttributedString(string: text, attributes: Theme.editorAttributes),
                                          goals: AppState.shared.settings.goals)
        editor = controller
        let view = QuickCheckView(
            controller: controller,
            appName: sourceApp?.localizedName ?? "the app",
            hasSelection: !text.trimmed.isEmpty,
            hotKey: AppState.shared.settings.hotKey(.quickCheck).display,
            onReplace: { [weak self] in self?.replaceInSource() },
            onSelectAll: { [weak self] in self?.selectAllAndCheck() },
            onClose: { [weak self] in self?.window?.orderOut(nil) })
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Theme.nsMidnight
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func replaceInSource() {
        guard let editor else { return }
        let newText = editor.text
        window?.orderOut(nil)
        guard newText != originalText else { return }
        let app = sourceApp
        let el = sourceElement
        let range = sourceRange
        let original = originalText
        Task { @MainActor in
            app?.activate()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let el, let range {
                let r = await TextInjector.replace(range: range, expected: original, with: newText, in: el)
                if r != .failed { return }
            }
            // The selection is still active in the source app, so pasting replaces it.
            await TextInjector.paste(newText)
        }
    }
}

struct QuickCheckView: View {
    @ObservedObject var controller: EditorController
    var appName: String
    var hasSelection: Bool
    var hotKey: String
    var onReplace: () -> Void
    var onSelectAll: () -> Void
    var onClose: () -> Void
    @ObservedObject var state = AppState.shared
    @State private var working: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                WaffleMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quick Check").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Text from \(appName)").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let tone = controller.result.tone, let p = tone.primary {
                    Label("\(p.emoji) \(tone.summary)", systemImage: "waveform").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                ScoreRing(score: controller.result.score, size: 44)
            }
            .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 10)

            if !hasSelection {
                VStack(spacing: 12) {
                    Image(systemName: "text.cursor").font(.system(size: 32)).foregroundStyle(Theme.syrup)
                    Text("Select the text you want to check in \(appName), then press \(hotKey).")
                        .font(.system(size: 14)).foregroundStyle(Theme.text)
                    Text("This works in Google Docs, Pages, Notion, Figma and any other app.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Button("Select all in \(appName) and check") { onSelectAll() }.buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    CheckedTextEditor(controller: controller, inset: NSSize(width: 22, height: 18))
                        .frame(minWidth: 380)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            EditorSuggestionList(controller: controller)
                        }
                        .padding(14)
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    .background(Theme.surface)
                }
                bottomBar
            }
        }
        .background(Theme.midnight)
        .environment(\.colorScheme, .dark)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error { ErrorBanner(message: error) }
            HStack(spacing: 6) {
                ForEach([RewriteMode.improve, .shorten, .professional, .friendly, .confident], id: \.self) { m in
                    Button(m.displayName) { rewrite(m) }.buttonStyle(ChipButtonStyle())
                }
                Button("Humanize") { humanize() }.buttonStyle(ChipButtonStyle())
                if let working { WorkingView(label: working) }
                Spacer()
            }
            HStack {
                Text("AI rewrites replace the whole text here. Press ⌘Z to undo.").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Copy") { copyToClipboard(controller.text) }.buttonStyle(GhostButtonStyle())
                Button("Cancel", action: onClose).buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                Button("Replace in \(appName)", action: onReplace).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .background(Theme.surface)
    }

    private func rewrite(_ m: RewriteMode) {
        let s = state.settings
        let text = controller.text
        working = "Rewriting…"; error = nil
        Task { @MainActor in
            do {
                let out = try await state.ai().rewrite(text, mode: m, goals: controller.goals, dialect: s.dialect, brand: s.activeBrandTone)
                controller.replaceAll(out, origin: .ai)
            } catch { self.error = error.localizedDescription }
            working = nil
        }
    }

    private func humanize() {
        let s = state.settings
        let text = controller.text
        working = "Humanizing…"; error = nil
        Task { @MainActor in
            do {
                let out = try await state.ai().humanize(text, voice: .natural, voiceSample: s.voiceSample, dialect: s.dialect)
                controller.replaceAll(out.rewrite.isEmpty ? LocalHumanizer().humanize(text) : out.rewrite, origin: .ai)
            } catch { self.error = error.localizedDescription }
            working = nil
        }
    }
}
