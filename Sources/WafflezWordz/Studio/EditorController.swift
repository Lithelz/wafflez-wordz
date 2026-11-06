import AppKit
import Combine
import SwiftUI
import WafflezCore

/// Owns one editable text: checking, underlines, suggestions, AI edits and authorship.
@MainActor
final class EditorController: ObservableObject {
    weak var textView: WafflezTextView?
    let state = AppState.shared

    @Published private(set) var text = ""
    @Published private(set) var result: AnalysisResult = .empty
    @Published private(set) var localSuggestions: [Suggestion] = []
    @Published private(set) var aiSuggestions: [Suggestion] = []
    @Published var filter: IssueCategory?
    @Published private(set) var selectedRange = NSRange(location: 0, length: 0)
    @Published var showAuthorship = false { didSet { refreshMarks() } }
    @Published var goals: WritingGoals { didSet { if goals != oldValue { scheduleAnalysis(immediate: true); scheduleSave() } } }
    @Published var ledger: AuthorshipLedger
    @Published var citationOffer: String?
    @Published var slashWorking = false

    /// Ranges highlighted by the AI detector or plagiarism checker.
    @Published var markedRanges: [NSRange] = [] { didSet { refreshMarks() } }
    @Published var title = "" { didSet { if title != oldValue { scheduleSave() } } }
    var documentID: UUID?
    private var saveWork: DispatchWorkItem?

    var checkingEnabled = true
    var onChange: (() -> Void)?
    private var dismissed: Set<String> = []
    private var analysisWork: DispatchWorkItem?
    private var initialAttributed: NSAttributedString

    private let card = PanelHost<SuggestionCardView>(allowsKey: false, level: .popUpMenu)
    private var cardID: UUID?
    private var cardHideWork: DispatchWorkItem?

    init(attributed: NSAttributedString, goals: WritingGoals, ledger: AuthorshipLedger = AuthorshipLedger()) {
        initialAttributed = attributed
        text = attributed.string
        self.goals = goals
        self.ledger = ledger
    }

    var suggestions: [Suggestion] {
        let all = (localSuggestions + aiSuggestions).sorted { $0.location < $1.location }
        guard let filter else { return all }
        return all.filter { $0.category == filter }
    }

    var allSuggestions: [Suggestion] { (localSuggestions + aiSuggestions).sorted { $0.location < $1.location } }

    var selectedText: String {
        guard selectedRange.length > 0, selectedRange.location + selectedRange.length <= (text as NSString).length else { return "" }
        return (text as NSString).substring(with: selectedRange)
    }

    // MARK: Text view hookup

    func attach(_ tv: WafflezTextView) {
        textView = tv
        tv.controller = self
        if tv.textStorage?.length == 0 && initialAttributed.length > 0 {
            tv.textStorage?.setAttributedString(initialAttributed)
            restyleForDarkMode(tv)
        }
        text = tv.string
        scheduleAnalysis(immediate: true)
    }

    /// RTF from older sessions may carry black text; make sure everything reads on midnight.
    private func restyleForDarkMode(_ tv: WafflezTextView) {
        guard let storage = tv.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let c = (value as? NSColor)?.usingColorSpace(.sRGB)
            if c == nil || (c!.brightnessComponent < 0.35) { storage.addAttribute(.foregroundColor, value: Theme.nsText, range: range) }
        }
        storage.endEditing()
    }

    var attributedText: NSAttributedString { textView?.attributedString() ?? NSAttributedString(string: text) }

    var rtfData: Data {
        let a = attributedText
        return (try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    // Called by the text view's delegate before every edit.
    func willChange(range: NSRange, replacement: String, origin: TextOrigin, source: String?) {
        let len = (replacement as NSString).length
        localSuggestions = localSuggestions.compactMap { $0.shifted(afterEditAt: range, insertedLength: len) }
        aiSuggestions = aiSuggestions.compactMap { $0.shifted(afterEditAt: range, insertedLength: len) }
        if ledger.isRecording { ledger.record(range: range, replacement: replacement, origin: origin, source: source) }
        hideCard()
    }

    func didChange() {
        guard let tv = textView else { return }
        text = tv.string
        if !markedRanges.isEmpty { markedRanges = [] }
        refreshMarks()
        scheduleAnalysis()
        onChange?()
        scheduleSave()
    }

    // MARK: Saving (Studio documents)

    func scheduleSave() {
        guard documentID != nil else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.persist() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func persist() {
        saveWork?.cancel()
        guard let id = documentID, var d = state.documents.first(where: { $0.id == id }) else { return }
        d.title = title.trimmed.isEmpty ? "Untitled" : title
        d.rtf = rtfData
        d.plainText = text
        d.goals = goals
        d.ledger = ledger
        state.save(d)
    }

    func selectionChanged(_ r: NSRange) {
        selectedRange = r
    }

    // MARK: Checking

    func scheduleAnalysis(immediate: Bool = false) {
        guard checkingEnabled else { return }
        analysisWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.analyze() } }
        analysisWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0.05 : 0.5), execute: work)
    }

    private func analyze() {
        let snapshot = text
        let capped = (snapshot as NSString).length > 120_000 ? (snapshot as NSString).substring(to: 120_000) : snapshot
        let r = state.analyzer.analyze(capped, config: state.config(goals: goals), includeTone: state.settings.toneDetectorEnabled)
        result = r
        localSuggestions = r.suggestions.filter { !dismissed.contains(key($0)) }
        // Drop AI suggestions that now overlap a fresh local one or whose text changed.
        let ns = snapshot as NSString
        aiSuggestions = aiSuggestions.filter { s in
            s.end <= ns.length && ns.substring(with: s.range) == s.original
        }
        refreshMarks()
    }

    private func key(_ s: Suggestion) -> String { "\(s.ruleID)|\(s.original)" }

    /// Draws underlines (and authorship colors) with temporary attributes, so the document itself is untouched.
    func refreshMarks() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        for r in markedRanges where r.location + r.length <= full.length {
            lm.addTemporaryAttribute(.backgroundColor, value: NSColor(hex: "#B58CFF").withAlphaComponent(0.28), forCharacterRange: r)
        }
        if showAuthorship {
            for (range, origin) in ledger.originRanges() where range.location + range.length <= full.length {
                lm.addTemporaryAttribute(.backgroundColor, value: NSColor(hex: origin.hexColor).withAlphaComponent(0.18), forCharacterRange: range)
            }
        }
        for s in allSuggestions where s.end <= full.length {
            if let filter, s.category != filter { continue }
            var r = s.range
            if s.ruleID == "long-sentence" { r.length = min(r.length, 24) }
            lm.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
                .underlineColor: Theme.nsColor(s.category),
            ], forCharacterRange: r)
            if s.id == cardID {
                lm.addTemporaryAttribute(.backgroundColor, value: Theme.nsColor(s.category).withAlphaComponent(0.2), forCharacterRange: r)
            }
        }
    }

    func suggestion(at index: Int) -> Suggestion? {
        allSuggestions.filter { index >= $0.location && index < ($0.ruleID == "long-sentence" ? $0.location + min($0.length, 24) : $0.end) }
            .min { $0.length < $1.length }
    }

    // MARK: Cards

    func showCard(_ s: Suggestion) {
        guard let tv = textView else { return }
        cardHideWork?.cancel()
        cardID = s.id
        var r = s.range
        if r.length > 40 { r.length = 24 }
        let screenRect = tv.firstRect(forCharacterRange: r, actualRange: nil)
        let ordered = allSuggestions
        let index = ordered.firstIndex { $0.id == s.id } ?? 0
        card.show(SuggestionCardView(
            suggestion: s, actions: actions(for: s), position: (index, ordered.count),
            onNext: { [weak self] in
                guard let self else { return }
                let list = self.allSuggestions
                guard !list.isEmpty else { return }
                let next = list[(index + 1) % list.count]
                self.reveal(next)
            }), at: NSPoint(x: screenRect.minX - 8, y: screenRect.minY - 4))
        refreshMarks()
    }

    func hideCard() {
        cardHideWork?.cancel()
        guard card.isVisible || cardID != nil else { return }
        card.hide()
        cardID = nil
        refreshMarks()
    }

    /// Hides the card soon unless the pointer moves onto it.
    func scheduleHideCard() {
        guard card.isVisible else { return }
        cardHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.card.panel.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                    self.scheduleHideCard()
                } else {
                    self.hideCard()
                }
            }
        }
        cardHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func cancelHideCard() { cardHideWork?.cancel() }
    var cardIsOpen: Bool { card.isVisible }
    var openCardID: UUID? { cardID }

    /// Scrolls to a suggestion and opens its card.
    func reveal(_ s: Suggestion) {
        guard let tv = textView else { return }
        tv.scrollRangeToVisible(s.range)
        tv.showFindIndicator(for: s.range)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated { self?.showCard(s) }
        }
    }

    func actions(for s: Suggestion) -> CardActions {
        CardActions(
            accept: { [weak self] rep in self?.apply(s, replacement: rep) },
            dismiss: { [weak self] in self?.dismiss(s) },
            addToDictionary: { [weak self] word in
                self?.state.addToDictionary(word)
                self?.dismiss(s)
                self?.scheduleAnalysis(immediate: true)
            },
            turnOffRule: { [weak self] rule in
                self?.state.disableRule(rule)
                self?.hideCard()
                self?.scheduleAnalysis(immediate: true)
            },
            report: { [weak self] note in self?.state.report(s, note: note) },
            reviewAll: nil,
            aiRewrite: { [weak self] sug in
                guard let self else { return sug.original }
                let set = self.state.settings
                return try await self.state.ai().rewrite(sug.original, mode: .clarify, goals: self.goals, dialect: set.dialect, brand: set.activeBrandTone)
            })
    }

    // MARK: Editing

    func apply(_ s: Suggestion, replacement: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        guard s.end <= ns.length, ns.substring(with: s.range) == s.original else { hideCard(); return }
        tv.replace(s.range, with: replacement, origin: .wafflez)
        localSuggestions.removeAll { $0.id == s.id }
        aiSuggestions.removeAll { $0.id == s.id }
        state.recordAccepted(s.category)
        hideCard()
        // Jump to the next suggestion, like flipping through cards.
        if let next = allSuggestions.first(where: { $0.location >= s.location }) ?? allSuggestions.first, cardIsOpenAfterAccept {
            reveal(next)
        }
    }

    var cardIsOpenAfterAccept = false

    func dismiss(_ s: Suggestion) {
        dismissed.insert(key(s))
        localSuggestions.removeAll { $0.id == s.id }
        aiSuggestions.removeAll { $0.id == s.id }
        state.recordDismissed()
        hideCard()
        refreshMarks()
    }

    func acceptAll(in category: IssueCategory? = nil) {
        guard let tv = textView else { return }
        let targets = allSuggestions.filter { !$0.replacements.isEmpty && (category == nil || $0.category == category) && $0.ruleID != "long-sentence" }
        // Apply from the end so earlier offsets stay valid.
        for s in targets.sorted(by: { $0.location > $1.location }) {
            let ns = tv.string as NSString
            guard s.end <= ns.length, ns.substring(with: s.range) == s.original else { continue }
            tv.replace(s.range, with: s.replacements[0], origin: .wafflez)
            state.recordAccepted(s.category)
        }
        localSuggestions.removeAll { targets.map(\.id).contains($0.id) }
        aiSuggestions.removeAll { targets.map(\.id).contains($0.id) }
        scheduleAnalysis(immediate: true)
    }

    func insert(_ s: String, origin: TextOrigin) {
        guard let tv = textView else { return }
        tv.replace(tv.selectedRange(), with: s, origin: origin)
    }

    func replaceSelection(_ s: String, origin: TextOrigin) {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        tv.replace(r, with: s, origin: origin)
        tv.setSelectedRange(NSRange(location: r.location, length: (s as NSString).length))
    }

    func replaceAll(_ s: String, origin: TextOrigin) {
        guard let tv = textView else { return }
        tv.replace(NSRange(location: 0, length: (tv.string as NSString).length), with: s, origin: origin)
    }

    /// Finds `edit.original` in the text and replaces it. Returns false if it's no longer there.
    @discardableResult
    func apply(edit: AIEdit, origin: TextOrigin = .ai) -> Bool {
        guard let tv = textView else { return false }
        let r = (tv.string as NSString).range(of: edit.original)
        guard r.location != NSNotFound else { return false }
        tv.replace(r, with: edit.replacement, origin: origin)
        return true
    }

    /// Shows an agent's edits as underlines and cards.
    func setAIEdits(_ edits: [AIEdit], ruleID: String) {
        aiSuggestions = EditLocator.suggestions(from: edits, in: text, ruleID: ruleID)
        refreshMarks()
    }

    func clearAIEdits() {
        aiSuggestions = []
        refreshMarks()
    }

    func highlight(_ range: NSRange) {
        guard let tv = textView, range.location + range.length <= (tv.string as NSString).length else { return }
        tv.scrollRangeToVisible(range)
        tv.showFindIndicator(for: range)
    }

    // MARK: Authorship

    func startAuthorship() {
        ledger.start(with: text)
        scheduleSave()
    }

    func stopAuthorship() {
        ledger.isRecording = false
        scheduleSave()
    }

    // MARK: Auto-citations

    func pastedFrom(url: String) {
        guard state.settings.autoCitations else { return }
        citationOffer = url
    }

    func addCitation(for url: String) {
        citationOffer = nil
        let style = state.settings.citationStyle
        Task { @MainActor in
            var source = CitationSource()
            source.url = url
            source.accessed = Date()
            source.title = URL(string: url)?.host ?? url
            if let ai = try? state.ai(), let page = try? await fetchPageText(url) {
                if let s = try? await ai.citationFromURL(url, pageText: page) { source = s }
            }
            let entry = CitationFormatter.bibliography(source, style: style)
            let marker = style == .mla ? "Works Cited" : (style == .apa ? "References" : "Bibliography")
            guard let tv = textView else { return }
            let current = tv.string
            if current.contains("\n\(marker)\n") {
                tv.replace(NSRange(location: (current as NSString).length, length: 0), with: "\n\(entry)", origin: .wafflez)
            } else {
                tv.replace(NSRange(location: (current as NSString).length, length: 0), with: "\n\n\(marker)\n\(entry)", origin: .wafflez)
            }
        }
    }

    private func fetchPageText(_ url: String) async throws -> String {
        guard let u = URL(string: url), u.scheme == "https" || u.scheme == "http" else { return "" }
        let (data, _) = try await URLSession.shared.data(from: u)
        let html = String(data: data.prefix(400_000), encoding: .utf8) ?? ""
        // Strip tags crudely; the model only needs title, byline and date.
        return html.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: Slash commands

    static let slashCommands: [(String, String)] = [
        ("/h1", "Large heading"), ("/h2", "Medium heading"), ("/h3", "Small heading"),
        ("/bullet", "Bulleted list item"), ("/todo", "Checkbox item"), ("/quote", "Quote"),
        ("/table", "3 × 3 table"), ("/divider", "Horizontal line"), ("/date", "Today's date"),
        ("/snippet name", "Insert a saved snippet"), ("/ai what to write", "Write with AI right here"),
    ]

    /// Runs a slash command on the current line if there is one. Returns true when handled.
    func handleSlashCommand() -> Bool {
        guard let tv = textView else { return false }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        var lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast(); lineRange.length -= 1 }
        let trimmed = line.trimmed
        guard trimmed.hasPrefix("/") else { return false }
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : ""

        func heading(_ size: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: Theme.nsText]
            tv.replace(lineRange, with: arg, origin: .typed)
            let r = NSRange(location: lineRange.location, length: (arg as NSString).length)
            if r.length > 0 { tv.textStorage?.addAttributes(attrs, range: r) }
            tv.typingAttributes = attrs
            tv.setSelectedRange(NSRange(location: r.location + r.length, length: 0))
            if r.length > 0 { tv.insertNewlineIgnoringFieldEditor(nil); tv.typingAttributes = Theme.editorAttributes }
        }

        switch cmd {
        case "/h1": heading(28)
        case "/h2": heading(22)
        case "/h3": heading(18)
        case "/bullet", "/list": tv.replace(lineRange, with: "•  " + arg, origin: .typed)
        case "/todo": tv.replace(lineRange, with: "☐  " + arg, origin: .typed)
        case "/quote":
            tv.replace(lineRange, with: "“" + arg + "”", origin: .typed)
            let r = NSRange(location: lineRange.location, length: (arg as NSString).length + 2)
            tv.textStorage?.addAttributes([.foregroundColor: NSColor(hex: "#9AA3C7"),
                                           .font: NSFontManager.shared.convert(Theme.editorFont, toHaveTrait: .italicFontMask)], range: r)
        case "/divider": tv.replace(lineRange, with: String(repeating: "─", count: 36) + "\n", origin: .typed)
        case "/date":
            let f = DateFormatter(); f.dateStyle = .long
            tv.replace(lineRange, with: f.string(from: Date()), origin: .typed)
        case "/table":
            tv.replace(lineRange, with: "", origin: .typed)
            let table = Self.makeTable(rows: 3, columns: 3)
            if tv.shouldChangeText(in: NSRange(location: lineRange.location, length: 0), replacementString: table.string) {
                tv.textStorage?.insert(table, at: lineRange.location)
                tv.didChangeText()
            }
        case "/snippet":
            let q = arg.lowercased().trimmed
            guard let snip = state.settings.snippets.first(where: { $0.shortcut.lowercased() == q || $0.name.lowercased() == q })
                ?? state.settings.snippets.first(where: { $0.name.lowercased().contains(q) && !q.isEmpty }) else { NSSound.beep(); return true }
            tv.replace(lineRange, with: snip.body, origin: .typed)
        case "/ai":
            guard !arg.trimmed.isEmpty else { NSSound.beep(); return true }
            let placeholder = "✨ Writing…"
            tv.replace(lineRange, with: placeholder, origin: .typed)
            let context = String(text.prefix(8000))
            slashWorking = true
            Task { @MainActor in
                defer { slashWorking = false }
                let s = state.settings
                let output: String
                do {
                    output = try await state.ai().compose(arg, context: context, goals: goals, dialect: s.dialect, brand: s.activeBrandTone)
                } catch {
                    output = "⚠️ " + error.localizedDescription
                }
                let r = (tv.string as NSString).range(of: placeholder)
                if r.location != NSNotFound { tv.replace(r, with: output, origin: .ai) }
            }
        default:
            return false
        }
        return true
    }

    static func makeTable(rows: Int, columns: Int) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        let out = NSMutableAttributedString()
        for r in 0..<rows {
            for c in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(NSColor(hex: "#2A3460"))
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setValue(100 / CGFloat(columns), type: .percentageValueType, for: .width)
                if r == 0 { block.backgroundColor = NSColor(hex: "#1A2244") }
                let p = NSMutableParagraphStyle()
                p.textBlocks = [block]
                let font = r == 0 ? NSFont.systemFont(ofSize: 14, weight: .semibold) : NSFont.systemFont(ofSize: 14)
                out.append(NSAttributedString(string: (r == 0 ? "Column \(c + 1)" : " ") + "\n",
                                              attributes: [.paragraphStyle: p, .font: font, .foregroundColor: Theme.nsText]))
            }
        }
        out.append(NSAttributedString(string: "\n", attributes: Theme.editorAttributes))
        return out
    }
}
