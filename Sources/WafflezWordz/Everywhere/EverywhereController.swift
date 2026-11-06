import AppKit
import ApplicationServices
import Combine
import SwiftUI
import WafflezCore

/// Wafflez in every app: watches the focused text field, checks it, and draws underlines, the widget and cards.
@MainActor
final class EverywhereController: ObservableObject {
    static let shared = EverywhereController()
    let state = AppState.shared

    // What we're attached to
    private(set) var element: AXUIElement?
    private var pid: pid_t = 0
    private(set) var bundleID: String?
    @Published private(set) var appName = ""
    private var lastText = ""
    private var lastFrame: CGRect = .zero
    private var rectsDirty = true
    private var webEnabledPIDs: Set<pid_t> = []

    // Results
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var tone: ToneResult?
    @Published private(set) var score = 100
    @Published private(set) var checking = false
    private var dismissed: Set<String> = []
    private var marks: [(suggestion: Suggestion, rect: CGRect)] = []
    private var analysisWork: DispatchWorkItem?
    private var wordsForInsights = 0

    // UI pieces
    private let overlay = UnderlineOverlay()
    private let widget = PanelHost<WidgetView>(allowsKey: false)
    private let card = PanelHost<SuggestionCardView>(allowsKey: false, level: .popUpMenu)
    private let toneCard = PanelHost<ToneCardView>(allowsKey: false, level: .popUpMenu)
    private let pill = PanelHost<SelectionPillView>(allowsKey: false)
    private let assistant = PanelHost<SelectionAssistantView>(allowsKey: true, level: .popUpMenu)
    private let compose = PanelHost<ComposeView>(allowsKey: true, level: .popUpMenu)
    private let definition = PanelHost<DefinitionView>(allowsKey: false, level: .popUpMenu)
    private let snippets = PanelHost<SnippetPickerView>(allowsKey: true, level: .popUpMenu)
    private let toast = PanelHost<UndoToastView>(allowsKey: false, level: .popUpMenu)
    let sideTab = SideTabController()
    let quickCheck = QuickCheckController()

    private var cardSuggestionID: UUID?
    private var hoverWork: DispatchWorkItem?
    private var cardHideWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var lastSelection: NSRange?
    private var lastUndo: (element: AXUIElement, range: NSRange, original: String, replacement: String)?
    private var monitors: [Any] = []
    private var timer: Timer?

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        installMonitors()
        state.onSettingsChanged = { [weak self] in
            self?.dismissed.removeAll()
            self?.lastText = ""
            self?.sideTab.refresh()
        }
        sideTab.start()
    }

    private func installMonitors() {
        let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            let clicks = e.clickCount
            MainActor.assumeIsolated { self?.mouseDown(clickCount: clicks) }
        }
        let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rectsDirty = true
                self?.hideCard()
            }
        }
        monitors = [moved, down, scroll].compactMap { $0 }
    }

    // MARK: Tracking

    private func tick() {
        guard state.settings.everywhereEnabled, !state.isPaused else { detach(); return }
        let trusted = AX.isTrusted
        if trusted != state.accessibilityTrusted { state.accessibilityTrusted = trusted }
        guard trusted else { detach(); return }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // When one of our own panels is active, keep everything as it is.
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        if state.isBlocked(front.bundleIdentifier) { detach(); return }

        if !webEnabledPIDs.contains(front.processIdentifier) {
            webEnabledPIDs.insert(front.processIdentifier)
            AX.enableWebAccessibility(pid: front.processIdentifier, bundleID: front.bundleIdentifier)
        }

        guard let el = AX.focusedElement(), AX.isEditableText(el) else {
            if !isMouseOverPanels() { detach() }
            return
        }
        if element == nil || !CFEqual(el, element!) {
            attach(el, app: front)
        }
        guard let text = AX.value(el) else { detach(); return }

        if text != lastText {
            lastText = text
            hideCard()
            // Drop underlines whose text changed so nothing is drawn in the wrong place, then re-check soon.
            let ns = text as NSString
            suggestions = suggestions.filter { $0.end <= ns.length && ns.substring(with: $0.range) == $0.original }
            rectsDirty = true
            scheduleAnalysis(text)
        }

        if let frame = AX.frame(el), frame != lastFrame {
            lastFrame = frame
            rectsDirty = true
        }
        if rectsDirty { layout() }
        updateSelection(el)
    }

    private func attach(_ el: AXUIElement, app: NSRunningApplication) {
        flushInsights()
        element = el
        pid = app.processIdentifier
        bundleID = app.bundleIdentifier
        appName = app.localizedName ?? "this app"
        lastText = ""
        lastFrame = .zero
        dismissed.removeAll()
        suggestions = []
        tone = nil
        lastSelection = nil
        hideCard()
        pill.hide()
    }

    func detach() {
        guard element != nil else { return }
        flushInsights()
        element = nil
        suggestions = []
        tone = nil
        marks = []
        overlay.hide()
        widget.hide()
        pill.hide()
        hideCard()
        toneCard.hide()
    }

    private func flushInsights() {
        if wordsForInsights > 0 { state.recordCheck(words: wordsForInsights, score: score) }
        wordsForInsights = 0
    }

    private func isMouseOverPanels() -> Bool {
        let p = NSEvent.mouseLocation
        return [card.panel, toneCard.panel, assistant.panel, compose.panel, definition.panel, snippets.panel]
            .contains { $0.isVisible && $0.frame.insetBy(dx: -8, dy: -8).contains(p) }
    }

    // MARK: Checking

    private func scheduleAnalysis(_ text: String) {
        analysisWork?.cancel()
        checking = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.analyze(text) }
        }
        analysisWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func analyze(_ text: String) {
        guard text == lastText else { return }
        let clipped = (text as NSString).length > 30_000 ? (text as NSString).substring(to: 30_000) : text
        let result = state.analyzer.analyze(clipped, config: state.analyzerConfig, includeTone: state.settings.toneDetectorEnabled)
        suggestions = result.suggestions.filter { !dismissed.contains(key($0)) }
        tone = result.tone
        score = result.score
        wordsForInsights = result.stats.words
        checking = false
        rectsDirty = true
        layout()
        sideTab.refresh()
    }

    private func key(_ s: Suggestion) -> String { "\(s.ruleID)|\(s.original)" }

    /// Recomputes where each underline sits on screen.
    private func layout() {
        rectsDirty = false
        guard let el = element, let axFrame = AX.frame(el) else { overlay.hide(); widget.hide(); return }
        let area = AX.toCocoa(axFrame)
        var newMarks: [(suggestion: Suggestion, rect: CGRect)] = []
        for s in suggestions.prefix(200) {
            // Long ranges (whole sentences) are marked under their first few words.
            var r = s.range
            if r.length > 40 { r.length = min(r.length, 24) }
            for b in AX.lineRects(for: r, in: el, text: lastText) {
                let rect = AX.toCocoa(b)
                // Skip text scrolled out of view.
                guard area.insetBy(dx: -2, dy: -2).contains(CGPoint(x: rect.midX, y: rect.midY)), rect.height < 80 else { continue }
                newMarks.append((suggestion: s, rect: rect))
            }
        }
        marks = newMarks
        overlay.show(marks.map {
            UnderlineOverlay.Mark(rect: $0.rect, color: Theme.nsColor($0.suggestion.category), highlighted: $0.suggestion.id == cardSuggestionID)
        }, in: area)
        positionWidget(area)
    }

    // MARK: Widget

    private var isEmailContext: Bool {
        if ["com.apple.mail", "com.microsoft.Outlook"].contains(bundleID ?? "") { return true }
        guard let win = AX.focusedWindow(pid: pid), let title = AX.title(win) else { return false }
        return title.contains("Gmail") || title.contains("Outlook") || title.hasPrefix("Re:") || title.contains("Inbox")
    }

    private func positionWidget(_ area: CGRect) {
        guard area.height >= 38 else { widget.hide(); return } // tiny one-line boxes are skipped
        let corner = state.settings.widgetAnchors[bundleID ?? ""] ?? 0
        let reply = isEmailContext
        let width: CGFloat = 28 + 28 + (tone != nil ? 28 : 0) + (reply ? 70 : 0) + 4
        let height: CGFloat = 32
        let origin: NSPoint
        switch corner {
        case 1: origin = NSPoint(x: area.maxX - width - 6, y: area.maxY - 4)               // top right
        case 2: origin = NSPoint(x: area.minX + 6, y: area.minY + height + 4)              // bottom left
        case 3: origin = NSPoint(x: area.minX + 6, y: area.maxY - 4)                       // top left
        default: origin = NSPoint(x: area.maxX - width - 6, y: area.minY + height + 4)    // bottom right
        }
        let counts = Dictionary(grouping: suggestions, by: \.category)
        let top = IssueCategory.allCases.sorted { $0.priority < $1.priority }.first { counts[$0] != nil }
        widget.show(WidgetView(
            count: suggestions.count, topCategory: top,
            toneEmoji: state.settings.toneDetectorEnabled ? tone?.primary?.emoji : nil,
            checking: checking && suggestions.isEmpty,
            showReply: reply,
            onOpen: { [weak self] in self?.openFirstCard() },
            onCompose: { [weak self] in self?.openCompose(reply: false) },
            onTone: { [weak self] in self?.showTone() },
            onReply: { [weak self] in self?.openCompose(reply: true) },
            onDragEnded: { [weak self] t in self?.moveWidget(by: t, area: area) }
        ), at: origin)
    }

    private func moveWidget(by translation: CGSize, area: CGRect) {
        let f = widget.panel.frame
        let p = CGPoint(x: f.midX + translation.width, y: f.midY - translation.height)
        let corners = [CGPoint(x: area.maxX, y: area.minY), CGPoint(x: area.maxX, y: area.maxY),
                       CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.minX, y: area.maxY)]
        let nearest = corners.enumerated().min { hypot($0.1.x - p.x, $0.1.y - p.y) < hypot($1.1.x - p.x, $1.1.y - p.y) }?.offset ?? 0
        state.settings.widgetAnchors[bundleID ?? ""] = nearest
        positionWidget(area)
    }

    // MARK: Hover and click

    private func suggestionAt(_ p: CGPoint) -> Suggestion? {
        // Prefer the smallest underline under the pointer (word fixes over whole-sentence hints).
        marks.filter { $0.rect.insetBy(dx: -1, dy: -4).contains(p) }
            .min { $0.suggestion.length < $1.suggestion.length }?.suggestion
    }

    private func mouseMoved() {
        guard element != nil else { return }
        let p = NSEvent.mouseLocation
        if card.isVisible && card.panel.frame.insetBy(dx: -6, dy: -6).contains(p) {
            cardHideWork?.cancel()
            return
        }
        if let s = suggestionAt(p) {
            cardHideWork?.cancel()
            guard s.id != cardSuggestionID else { return }
            hoverWork?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.showCard(s) } }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        } else {
            hoverWork?.cancel()
            if card.isVisible && cardHideWork == nil {
                let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hideCard() } }
                cardHideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
            }
        }
    }

    private func mouseDown(clickCount: Int) {
        let p = NSEvent.mouseLocation
        if let s = suggestionAt(p) {
            showCard(s)
        } else if !isMouseOverPanels() {
            hideCard()
            toneCard.hide()
            definition.hide()
        }
        if clickCount == 2 && state.settings.definitionsEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.showDefinitionForSelection(at: p) }
            }
        }
    }

    // MARK: Cards

    func openFirstCard() {
        if let first = suggestions.sorted(by: { $0.location < $1.location }).first {
            showCard(first)
        } else {
            openCompose(reply: false)
        }
    }

    func showCard(_ s: Suggestion) {
        hoverWork?.cancel()
        cardHideWork?.cancel()
        cardHideWork = nil
        cardSuggestionID = s.id
        let ordered = suggestions.sorted { $0.location < $1.location }
        let index = ordered.firstIndex { $0.id == s.id } ?? 0
        let anchor = marks.first { $0.suggestion.id == s.id }?.rect ?? widget.panel.frame
        let view = SuggestionCardView(
            suggestion: s, actions: cardActions(for: s),
            position: (index, ordered.count),
            onNext: { [weak self] in
                guard let self, !ordered.isEmpty else { return }
                let next = ordered[(index + 1) % ordered.count]
                if self.suggestions.contains(where: { $0.id == next.id }) { self.showCard(next) }
            })
        card.show(view, at: NSPoint(x: anchor.minX - 8, y: anchor.minY - 6))
        overlayRefresh()
    }

    func hideCard() {
        hoverWork?.cancel()
        cardHideWork?.cancel()
        cardHideWork = nil
        guard card.isVisible || cardSuggestionID != nil else { return }
        card.hide()
        cardSuggestionID = nil
        overlayRefresh()
    }

    private func overlayRefresh() {
        guard let el = element, let f = AX.frame(el) else { return }
        overlay.show(marks.map {
            UnderlineOverlay.Mark(rect: $0.rect, color: Theme.nsColor($0.suggestion.category), highlighted: $0.suggestion.id == cardSuggestionID)
        }, in: AX.toCocoa(f))
    }

    func cardActions(for s: Suggestion) -> CardActions {
        CardActions(
            accept: { [weak self] rep in self?.accept(s, with: rep) },
            dismiss: { [weak self] in self?.dismiss(s) },
            addToDictionary: { [weak self] word in
                self?.state.addToDictionary(word)
                self?.dismiss(s)
            },
            turnOffRule: { [weak self] rule in
                self?.state.disableRule(rule)
                self?.hideCard()
            },
            report: { [weak self] note in self?.state.report(s, note: note) },
            reviewAll: { [weak self] in
                self?.hideCard()
                self?.sideTab.open(tab: .suggestions)
            },
            aiRewrite: { [weak self] sug in
                guard let self else { return sug.original }
                let set = self.state.settings
                return try await self.state.ai().rewrite(sug.original, mode: .clarify, goals: set.goals, dialect: set.dialect, brand: set.activeBrandTone)
            }
        )
    }

    func accept(_ s: Suggestion, with replacement: String) {
        guard let el = element else { return }
        hideCard()
        Task { @MainActor in
            let result = await TextInjector.replace(range: s.range, expected: s.original, with: replacement, in: el)
            switch result {
            case .failed:
                copyToClipboard(replacement)
                showToast("This field can't be edited directly — the fix is on your clipboard.", undo: nil)
            case .replaced, .pasted:
                state.recordAccepted(s.category)
                suggestions.removeAll { $0.id == s.id }
                lastUndo = (el, NSRange(location: s.location, length: (replacement as NSString).length), s.original, replacement)
                showToast(replacement.isEmpty ? "Removed \"\(s.original.trimmed)\"" : "Changed to \"\(replacement)\"", undo: { [weak self] in self?.undo() })
            }
            rectsDirty = true
            sideTab.refresh()
        }
    }

    func dismiss(_ s: Suggestion) {
        dismissed.insert(key(s))
        suggestions.removeAll { $0.id == s.id }
        state.recordDismissed()
        hideCard()
        rectsDirty = true
        sideTab.refresh()
    }

    private func undo() {
        guard let u = lastUndo else { return }
        lastUndo = nil
        toast.hide()
        Task { @MainActor in
            _ = await TextInjector.replace(range: u.range, expected: u.replacement, with: u.original, in: u.element)
        }
    }

    private func showToast(_ message: String, undo: (() -> Void)?) {
        toastWork?.cancel()
        let anchor = widget.panel.isVisible ? widget.panel.frame : NSRect(origin: NSEvent.mouseLocation, size: .zero)
        toast.show(UndoToastView(message: message, onUndo: undo ?? { [weak self] in self?.toast.hide() }),
                   at: NSPoint(x: anchor.maxX - 260, y: anchor.minY - 8))
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.toast.hide() } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func showTone() {
        guard let tone else { return }
        let f = widget.panel.frame
        toneCard.show(ToneCardView(tone: tone, onClose: { [weak self] in self?.toneCard.hide() }), at: NSPoint(x: f.maxX - 290, y: f.minY - 6))
    }

    // MARK: Selection assistant

    private func updateSelection(_ el: AXUIElement) {
        guard state.settings.selectionAssistantEnabled else { pill.hide(); return }
        let sel = AX.selectedRange(el)
        guard sel != lastSelection else { return }
        lastSelection = sel
        guard let sel, sel.length >= 3,
              let selected = AX.selectedText(el), selected.split(whereSeparator: \.isWhitespace).count >= 2,
              let b = AX.bounds(for: NSRange(location: sel.location, length: 1), in: el) else {
            pill.hide()
            return
        }
        let r = AX.toCocoa(b)
        pill.show(SelectionPillView(onTap: { [weak self] in self?.openAssistantForSelection() }),
                  at: NSPoint(x: r.minX - 32, y: r.maxY + 1))
    }

    /// Opens the rewrite menu for the current selection (AX first, clipboard as a fallback for canvas editors like Google Docs).
    func openAssistantForSelection() {
        pill.hide()
        Task { @MainActor in
            let front = NSWorkspace.shared.frontmostApplication
            let grabbed = await grabSelection()
            let el = grabbed.element
            let range = grabbed.range
            guard let text = grabbed.text, !text.trimmed.isEmpty else {
                showToast("Select some text first, then try again.", undo: nil)
                return
            }
            let anchor: NSPoint = {
                if let el, let range, let b = AX.bounds(for: NSRange(location: range.location, length: 1), in: el) {
                    let r = AX.toCocoa(b)
                    return NSPoint(x: r.minX, y: r.minY - 8)
                }
                let m = NSEvent.mouseLocation
                return NSPoint(x: m.x - 190, y: m.y - 12)
            }()
            let ctx = SelectionContext(
                text: text, appName: front?.localizedName ?? "this app",
                replace: { [weak self] newText in
                    self?.assistant.hide()
                    Task { @MainActor in
                        if let el, let range {
                            let r = await TextInjector.replace(range: range, expected: text, with: newText, in: el)
                            if r == .failed { await TextInjector.paste(newText) }
                        } else {
                            front?.activate()
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            await TextInjector.paste(newText)
                        }
                        self?.state.recordAccepted(.clarity)
                    }
                },
                close: { [weak self] in self?.assistant.hide() })
            assistant.show(SelectionAssistantView(context: ctx), at: anchor, key: true)
        }
    }

    /// Reads the selected text through Accessibility, or by copying it when the app doesn't expose it.
    private func grabSelection() async -> (text: String?, element: AXUIElement?, range: NSRange?) {
        if let focused = AX.focusedElement(), let t = AX.selectedText(focused), !t.trimmed.isEmpty {
            return (t, focused, AX.selectedRange(focused))
        }
        return (await TextInjector.copySelection(), nil, nil)
    }

    // MARK: Compose, snippets, definitions

    func openCompose(reply: Bool) {
        let pidNow = pid
        let el = element
        let f = widget.panel.isVisible ? widget.panel.frame : NSRect(origin: NSEvent.mouseLocation, size: .zero)
        compose.show(ComposeView(
            screenContext: {
                guard let win = AX.focusedWindow(pid: pidNow) else { return "" }
                return AX.text(in: win, limit: 15000)
            },
            insert: { [weak self] text in
                self?.compose.hide()
                Task { @MainActor in _ = await TextInjector.insert(text, in: el) }
            },
            close: { [weak self] in self?.compose.hide() },
            startInReplyMode: reply
        ), at: NSPoint(x: f.maxX - 420, y: f.minY - 6), key: true)
    }

    func openSnippets() {
        let el = element ?? AX.focusedElement()
        let m = NSEvent.mouseLocation
        snippets.show(SnippetPickerView(
            insert: { [weak self] body in
                self?.snippets.hide()
                Task { @MainActor in _ = await TextInjector.insert(body, in: el) }
            },
            close: { [weak self] in self?.snippets.hide() }
        ), at: NSPoint(x: m.x - 180, y: m.y - 10), key: true)
    }

    private func showDefinitionForSelection(at point: CGPoint) {
        guard let focused = AX.focusedElement(), let word = AX.selectedText(focused)?.trimmed,
              !word.isEmpty, !word.contains(" "), word.count < 40, word.rangeOfCharacter(from: .letters) != nil else { return }
        let editable = AX.isEditableText(focused)
        let range = AX.selectedRange(focused)
        var sentence = word
        if let full = AX.value(focused), let range {
            let ns = full as NSString
            let start = max(0, range.location - 120)
            sentence = ns.substring(with: NSRange(location: start, length: min(ns.length - start, range.length + 240)))
        }
        definition.show(DefinitionView(
            word: word, definition: Definitions.define(word), canReplace: editable, sentence: sentence,
            replace: { [weak self] syn in
                self?.definition.hide()
                Task { @MainActor in
                    if let range { _ = await TextInjector.replace(range: range, expected: word, with: syn, in: focused) }
                }
            },
            close: { [weak self] in self?.definition.hide() }
        ), at: NSPoint(x: point.x - 20, y: point.y - 14))
    }

    // MARK: Side panel support

    /// Applies a suggestion from the side panel list.
    func acceptFromList(_ s: Suggestion) {
        accept(s, with: s.replacements.first ?? "")
    }

    var screenText: String {
        guard pid != 0, let win = AX.focusedWindow(pid: pid) else { return "" }
        return AX.text(in: win, limit: 20000)
    }

    var currentFieldText: String { lastText }
    var currentPID: pid_t { pid }
}
