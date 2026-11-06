import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WafflezCore

enum StudioSection: String, Hashable, CaseIterable, Identifiable {
    case documents, chat, agents, humanizer, detector, plagiarism, citations
    case styleGuide, brandTones, snippets, knowledge, dictionary
    case insights, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .documents: return "Documents"
        case .chat: return "AI Chat"
        case .agents: return "Agents"
        case .humanizer: return "Humanizer"
        case .detector: return "AI Detector"
        case .plagiarism: return "Plagiarism Checker"
        case .citations: return "Citations"
        case .styleGuide: return "Style guide"
        case .brandTones: return "Brand tones"
        case .snippets: return "Snippets"
        case .knowledge: return "Knowledge Share"
        case .dictionary: return "Dictionary"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .documents: return "doc.text"
        case .chat: return "bubble.left.and.bubble.right"
        case .agents: return "square.grid.2x2"
        case .humanizer: return "person.wave.2"
        case .detector: return "cpu"
        case .plagiarism: return "doc.on.doc"
        case .citations: return "quote.opening"
        case .styleGuide: return "ruler"
        case .brandTones: return "megaphone"
        case .snippets: return "text.badge.plus"
        case .knowledge: return "books.vertical"
        case .dictionary: return "character.book.closed"
        case .insights: return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class StudioNavigation: ObservableObject {
    @Published var section: StudioSection? = .documents
    @Published var documentID: UUID?
}

/// The Studio window: Wafflez's own app for writing with every AI tool beside you.
@MainActor
final class StudioWindow: NSObject, NSWindowDelegate {
    static let shared = StudioWindow()
    let nav = StudioNavigation()
    private var window: NSWindow?

    func show(section: StudioSection? = nil) {
        if let section { nav.section = section }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Wafflez Studio"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Theme.nsMidnight
            w.minSize = NSSize(width: 980, height: 620)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentViewController = NSHostingController(rootView: StudioView(nav: nav))
            w.setFrameAutosaveName("WafflezStudio")
            if !w.setFrameUsingName("WafflezStudio") { w.center() }
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func open(document id: UUID) {
        nav.documentID = id
        show(section: .documents)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app when the Studio closes.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}

struct StudioView: View {
    @ObservedObject var nav: StudioNavigation
    @ObservedObject var state = AppState.shared
    @State private var showWelcome = false

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.section) {
                Section("Write") {
                    row(.documents)
                    row(.chat)
                }
                Section("AI tools") {
                    row(.agents); row(.humanizer); row(.detector); row(.plagiarism); row(.citations)
                }
                Section("Team") {
                    row(.styleGuide); row(.brandTones); row(.snippets); row(.knowledge); row(.dictionary)
                }
                Section {
                    row(.insights); row(.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    WaffleMark(size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Wafflez Wordz").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                        Text(statusLine).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 8)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.midnight)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.syrup)
        .onAppear { if !state.settings.hasSeenWelcome { showWelcome = true } }
        .sheet(isPresented: $showWelcome) {
            WelcomeView { state.settings.hasSeenWelcome = true; showWelcome = false }
        }
    }

    private var statusLine: String {
        if !state.accessibilityTrusted { return "Needs Accessibility permission" }
        if state.isPaused { return "Paused" }
        return state.settings.everywhereEnabled ? "On in every app" : "Off in other apps"
    }

    private func row(_ s: StudioSection) -> some View {
        Label(s.title, systemImage: s.symbol).tag(s)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.section ?? .documents {
        case .documents: DocumentsScreen(nav: nav)
        case .chat: StudioChatScreen()
        case .agents: ToolWorkspace(initial: .proofreader, title: "Agents", subtitle: "Single-purpose AI tools. Pick one, run it on your text, and insert or dismiss its suggestions.", showGrid: true)
        case .humanizer: ToolWorkspace(initial: .humanizer, title: "AI Humanizer", subtitle: "Make AI-assisted drafts sound like you wrote them, without changing the meaning.", showGrid: false)
        case .detector: ToolWorkspace(initial: .aiDetector, title: "AI Detector", subtitle: "Estimate how much of a text reads as AI-written, sentence by sentence.", showGrid: false)
        case .plagiarism: ToolWorkspace(initial: .plagiarism, title: "Plagiarism Checker", subtitle: "Check for overlap with your library, your sources and the web.", showGrid: false)
        case .citations: ToolWorkspace(initial: .citationFinder, title: "Citations", subtitle: "Find sources for your claims and format citations in APA, MLA or Chicago.", showGrid: false)
        case .styleGuide: StyleGuideScreen()
        case .brandTones: BrandTonesScreen()
        case .snippets: SnippetsScreen()
        case .knowledge: KnowledgeScreen()
        case .dictionary: DictionaryScreen()
        case .insights: InsightsScreen()
        case .settings: SettingsScreen()
        }
    }
}

// MARK: - Documents

struct DocumentsScreen: View {
    @ObservedObject var nav: StudioNavigation
    @ObservedObject var state = AppState.shared
    @State private var query = ""
    @AppStorage("wz.showDocList") private var showList = true

    var filtered: [WDocument] {
        let q = query.lowercased().trimmed
        guard !q.isEmpty else { return state.documents }
        return state.documents.filter { $0.title.lowercased().contains(q) || $0.plainText.lowercased().contains(q) }
    }

    var body: some View {
        HSplitView {
            if showList {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Search documents", text: $query).textFieldStyle(.plain)
                    Menu {
                        Button("New document") { newDoc() }
                        Button("Import file…") { importFile() }
                    } label: {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.syrup)
                    } primaryAction: { newDoc() }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("New document")
                }
                .padding(10)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 12).padding(.top, 38).padding(.bottom, 8)
                List(selection: $nav.documentID) {
                    ForEach(filtered) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(d.preview).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                            Text(d.modified.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 4)
                        .tag(d.id)
                        .contextMenu {
                            Button("Duplicate") {
                                var copy = state.newDocument(title: d.title + " copy", text: d.plainText)
                                copy.rtf = d.rtf
                                state.save(copy)
                            }
                            Button("Export as text…") { export(d) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                if nav.documentID == d.id { nav.documentID = nil }
                                state.delete(d)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            .background(Theme.surface.opacity(0.6))
            }

            Group {
                if let id = nav.documentID, let doc = state.documents.first(where: { $0.id == id }) {
                    EditorScreen(doc: doc).id(doc.id)
                } else {
                    VStack(spacing: 14) {
                        WaffleMark(size: 54)
                        Text("Pick a document or start a new one").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        Button("New document") { newDoc() }.buttonStyle(PrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 520)
        }
        .onAppear { if nav.documentID == nil { nav.documentID = state.documents.first?.id } }
    }

    private func newDoc() {
        let d = state.newDocument()
        nav.documentID = d.id
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .rtf, .pdf, .html, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url, let a = DocumentImport.attributed(from: url) else { return }
        var d = state.newDocument(title: url.deletingPathExtension().lastPathComponent, text: a.string)
        d.rtf = (try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        state.save(d)
        nav.documentID = d.id
    }

    private func export(_ d: WDocument) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = d.title + ".txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url { try? d.plainText.write(to: url, atomically: true, encoding: .utf8) }
    }
}

// MARK: - Editor screen

struct EditorScreen: View {
    @StateObject private var controller: EditorController
    @StateObject private var chat = ChatSession()
    @ObservedObject var state = AppState.shared
    @State private var inspectorTab: InspectorTab = .review
    @State private var showInspector = true
    @State private var agent: AgentKind?
    @State private var showGoals = false
    @State private var selectionResult: String?
    @State private var selectionWorking = false
    @State private var selectionError: String?
    @AppStorage("wz.showDocList") private var showList = true

    enum InspectorTab: String, CaseIterable, Identifiable {
        case review = "Review", agents = "Agents", chat = "Chat", stats = "Stats"
        var id: String { rawValue }
    }

    init(doc: WDocument) {
        let c = EditorController(attributed: doc.attributed, goals: doc.goals, ledger: doc.ledger)
        c.documentID = doc.id
        c.title = doc.title
        _controller = StateObject(wrappedValue: c)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                if let url = controller.citationOffer { citationBanner(url) }
                CheckedTextEditor(controller: controller, inset: NSSize(width: 30, height: 24))
                if !controller.selectedText.trimmed.isEmpty && controller.selectedText.split(separator: " ").count >= 2 {
                    selectionBar
                }
            }
            if showInspector {
                Divider().overlay(Theme.stroke)
                inspector.frame(width: 330)
            }
        }
        .onDisappear { controller.persist(); controller.hideCard() }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { withAnimation { showList.toggle() } } label: { Image(systemName: "sidebar.squares.left") }
                    .buttonStyle(.plain).foregroundStyle(showList ? Theme.syrup : Theme.textSecondary)
                    .help(showList ? "Hide the document list" : "Show the document list")
                Text("\(controller.result.stats.words) words · \(controller.result.stats.readingTimeSeconds / 60 + 1) min read")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                if controller.slashWorking { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                Button { showGoals.toggle() } label: { Image(systemName: "target") }
                    .buttonStyle(GhostButtonStyle())
                    .help("Goals: audience, formality, domain and intent")
                    .popover(isPresented: $showGoals) { GoalsView(goals: $controller.goals).padding(16).frame(width: 320) }
                Button {
                    if controller.ledger.isRecording { controller.showAuthorship.toggle() } else { controller.startAuthorship() }
                } label: {
                    Image(systemName: "touchid").foregroundStyle(controller.ledger.isRecording ? Theme.success : Theme.textSecondary)
                }
                .buttonStyle(GhostButtonStyle())
                .help(controller.ledger.isRecording ? "Authorship is on. Click to color text by origin." : "Turn on Authorship")
                Menu {
                    Section("Slash commands — type on a new line, then Return") {
                        ForEach(EditorController.slashCommands.map { "\($0.0)  —  \($0.1)" }, id: \.self) { Text($0) }
                    }
                    Divider()
                    Button("Copy all text") { copyToClipboard(controller.text) }
                    Button("Export as Rich Text…") { exportRTF() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Button { withAnimation { showInspector.toggle() } } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(GhostButtonStyle())
            }
            TextField("Title", text: $controller.title)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 8)
        .background(Theme.midnight)
    }

    private func citationBanner(_ url: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening").foregroundStyle(Theme.syrup)
            Text("You pasted from \(URL(string: url)?.host ?? url). Add a citation?").font(.system(size: 12.5)).foregroundStyle(Theme.text)
            Spacer()
            Button("Add citation") { controller.addCitation(for: url) }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
            Button("Not now") { controller.citationOffer = nil }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
        .background(Theme.syrup.opacity(0.08))
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectionError { ErrorBanner(message: selectionError) }
            if let result = selectionResult {
                HStack(alignment: .top) {
                    Text(result).font(.system(size: 13)).foregroundStyle(Theme.text).textSelection(.enabled).lineLimit(6)
                    Spacer()
                    Button("Accept") { controller.replaceSelection(result, origin: .ai); selectionResult = nil }.buttonStyle(PrimaryButtonStyle())
                    Button("Copy") { copyToClipboard(result) }.buttonStyle(GhostButtonStyle())
                    Button { selectionResult = nil } label: { Image(systemName: "xmark") }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.indigo).frame(width: 4, height: 22)
                ForEach([RewriteMode.improve, .shorten, .professional, .friendly, .confident, .simplify], id: \.self) { m in
                    Button(m.displayName) { rewriteSelection(m) }
                        .buttonStyle(ChipButtonStyle())
                }
                Menu("Translate") {
                    ForEach(WafflezAI.languages, id: \.self) { lang in
                        Button(lang) { runSelection { ai, text in try await ai.translate(text, to: lang) } }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                Button("Explain") { runSelection { ai, text in try await ai.explain(text) } }.buttonStyle(ChipButtonStyle())
                if selectionWorking { ProgressView().controlSize(.small) }
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.surface)
    }

    private func rewriteSelection(_ m: RewriteMode) {
        let goals = controller.goals
        let s = state.settings
        runSelection { ai, text in
            try await ai.rewrite(text, mode: m, goals: goals, dialect: s.dialect, brand: s.activeBrandTone)
        }
    }

    private func runSelection(_ work: @escaping (WafflezAI, String) async throws -> String) {
        let text = controller.selectedText
        selectionWorking = true
        selectionError = nil
        Task { @MainActor in
            do {
                let ai = try state.ai()
                selectionResult = try await work(ai, text)
            } catch { selectionError = error.localizedDescription }
            selectionWorking = false
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("", selection: $inspectorTab) { ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 14).padding(.top, 36).padding(.bottom, 10)
            Divider().overlay(Theme.stroke)
            switch inspectorTab {
            case .review:
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            ScoreRing(score: controller.result.score, size: 62)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overall score").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                                Text("Based on your goals: \(controller.goals.formality.displayName.lowercased()), \(controller.goals.domain.displayName.lowercased()).")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        EditorSuggestionList(controller: controller)
                    }
                    .padding(14)
                }
            case .agents:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let agent {
                            Button { self.agent = nil } label: { Label("All agents", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Theme.syrup)
                            AgentRunnerView(kind: agent, controller: controller, chat: chat)
                        } else {
                            AgentGrid(columns: 2) { agent = $0 }
                        }
                    }
                    .padding(14)
                }
            case .chat:
                ChatView(session: chat, contextProvider: { (controller.text, controller.title.isEmpty ? "your document" : controller.title) },
                         insertAction: { controller.insert($0, origin: .ai) }, compact: true)
            case .stats:
                ScrollView { StatsView(result: controller.result).padding(14) }
            }
        }
        .background(Theme.surface)
    }

    private func exportRTF() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (controller.title.isEmpty ? "Untitled" : controller.title) + ".rtf"
        panel.allowedContentTypes = [.rtf]
        if panel.runModal() == .OK, let url = panel.url { try? controller.rtfData.write(to: url) }
    }
}

struct GoalsView: View {
    @Binding var goals: WritingGoals
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goals").font(.system(size: 15, weight: .bold))
            Text("Wafflez tailors suggestions to who you're writing for.").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            Picker("Audience", selection: $goals.audience) { ForEach(Audience.allCases) { Text($0.displayName).tag($0) } }
            Picker("Formality", selection: $goals.formality) { ForEach(Formality.allCases) { Text($0.displayName).tag($0) } }
            Picker("Domain", selection: $goals.domain) { ForEach(Domain.allCases) { Text($0.displayName).tag($0) } }
            Picker("Intent", selection: $goals.intent) { ForEach(Intent.allCases) { Text($0.displayName).tag($0) } }
        }
    }
}

struct StatsView: View {
    var result: AnalysisResult
    var body: some View {
        let s = result.stats
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                stat("Words", "\(s.words)")
                stat("Characters", "\(s.characters)")
                stat("Sentences", "\(s.sentences)")
                stat("Paragraphs", "\(s.paragraphs)")
                stat("Reading time", duration(s.readingTimeSeconds))
                stat("Speaking time", duration(s.speakingTimeSeconds))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Readability").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Text("\(Int(s.fleschReadingEase)) · \(s.readabilityLabel)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Average sentence: \(String(format: "%.1f", s.averageSentenceLength)) words · Unique words: \(Int(s.uniqueWordRatio * 100))%")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10)
            if let tone = result.tone {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tone").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    ToneDetailView(tone: tone)
                }
                .card(padding: 10)
            } else {
                Text("Write at least \(ToneDetector.minimumCharacters) characters to detect tone.").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions by category").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                ForEach(IssueCategory.allCases) { c in
                    HStack { CategoryDot(category: c); Text(c.displayName).foregroundStyle(Theme.text); Spacer(); Text("\(result.count(c))").foregroundStyle(Theme.textSecondary) }
                        .font(.system(size: 12.5))
                }
            }
            .card(padding: 10)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min \(seconds % 60) sec"
    }
}

// MARK: - Chat screen

struct StudioChatScreen: View {
    @StateObject private var session = ChatSession()
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "AI Chat", subtitle: "Ask, research, draft and brainstorm. Attach files, or point it at any open window.")
                .padding(.horizontal, 24).padding(.top, 38).padding(.bottom, 12)
            ChatView(session: session, contextProvider: nil, attachTargets: { SidePanelView.windowTargets() })
        }
    }
}

// MARK: - Tool workspace (Agents, Humanizer, Detector, Plagiarism, Citations)

struct ToolWorkspace: View {
    let initial: AgentKind
    let title: String
    let subtitle: String
    let showGrid: Bool
    @StateObject private var controller = EditorController(attributed: NSAttributedString(string: "", attributes: Theme.editorAttributes), goals: AppState.shared.settings.goals)
    @StateObject private var chat = ChatSession()
    @ObservedObject var state = AppState.shared
    @State private var agent: AgentKind?
    @State private var linkedDoc: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                SectionHeader(title: title, subtitle: subtitle)
                Menu {
                    ForEach(state.documents) { d in Button(d.title) { load(d) } }
                    Divider()
                    Button("Import a file…") { importFile() }
                    Button("Paste from clipboard") {
                        controller.replaceAll(NSPasteboard.general.string(forType: .string) ?? "", origin: .pasted)
                        linkedDoc = nil
                    }
                } label: { Label("Load text", systemImage: "tray.and.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                if let linkedDoc {
                    Button("Save back to document") { save(to: linkedDoc) }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                }
            }
            .padding(.horizontal, 24).padding(.top, 38).padding(.bottom, 12)
            HSplitView {
                ZStack(alignment: .topLeading) {
                    CheckedTextEditor(controller: controller, inset: NSSize(width: 26, height: 20))
                    if controller.text.isEmpty {
                        Text("Paste or type your text here, or load a document.")
                            .font(.system(size: 15)).foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 32).padding(.top, 20).allowsHitTesting(false)
                    }
                }
                .frame(minWidth: 420)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if showGrid && agent == nil {
                            AgentGrid(columns: 2) { agent = $0 }
                        } else {
                            if showGrid {
                                Button { agent = nil } label: { Label("All agents", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Theme.syrup)
                            }
                            AgentRunnerView(kind: agent ?? initial, controller: controller, chat: chat)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                .background(Theme.surface)
            }
        }
        .onAppear { if !showGrid { agent = initial } }
    }

    private func load(_ d: WDocument) {
        controller.replaceAll(d.plainText, origin: .existing)
        controller.title = d.title
        controller.documentID = nil
        linkedDoc = d.id
    }

    private func save(to id: UUID) {
        guard var d = state.documents.first(where: { $0.id == id }) else { return }
        d.plainText = controller.text
        d.rtf = controller.rtfData
        state.save(d)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .rtf, .pdf, .html, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url, let t = DocumentImport.text(from: url) else { return }
        controller.replaceAll(t, origin: .pasted)
        linkedDoc = nil
    }
}
