import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WafflezCore

/// Single-purpose AI tools. Each reads the whole draft and returns suggestions you can insert or dismiss.
enum AgentKind: String, CaseIterable, Identifiable {
    case proofreader, paraphraser, humanizer, expertReview, readerReactions, aiGrader, citationFinder, aiDetector, plagiarism, authorship, chat, resume

    var id: String { rawValue }
    var name: String {
        switch self {
        case .proofreader: return "Proofreader"
        case .paraphraser: return "Paraphraser"
        case .humanizer: return "Humanizer"
        case .expertReview: return "Expert Review"
        case .readerReactions: return "Reader Reactions"
        case .aiGrader: return "AI Grader"
        case .citationFinder: return "Citation Finder"
        case .aiDetector: return "AI Detector"
        case .plagiarism: return "Plagiarism Checker"
        case .authorship: return "Authorship"
        case .chat: return "AI Chat"
        case .resume: return "Resume Builder"
        }
    }
    var symbol: String {
        switch self {
        case .proofreader: return "checkmark.seal"
        case .paraphraser: return "arrow.triangle.2.circlepath"
        case .humanizer: return "person.wave.2"
        case .expertReview: return "graduationcap"
        case .readerReactions: return "person.2.wave.2"
        case .aiGrader: return "list.bullet.clipboard"
        case .citationFinder: return "quote.opening"
        case .aiDetector: return "cpu"
        case .plagiarism: return "doc.on.doc"
        case .authorship: return "touchid"
        case .chat: return "bubble.left.and.bubble.right"
        case .resume: return "person.text.rectangle"
        }
    }
    var blurb: String {
        switch self {
        case .proofreader: return "Fixes grammar, clarity, structure and flow, tuned to your audience."
        case .paraphraser: return "Rewrites in a style you pick — or in your own voice."
        case .humanizer: return "Makes AI-assisted writing sound natural without changing the meaning."
        case .expertReview: return "Feedback inspired by experts in your subject to strengthen your argument."
        case .readerReactions: return "Predicts what a reader will take away, question or misunderstand."
        case .aiGrader: return "Rubric-based feedback and an estimated grade before you submit."
        case .citationFinder: return "Finds real sources that support or dispute your claims, formatted for you."
        case .aiDetector: return "Estimates how much of the text reads as AI-written."
        case .plagiarism: return "Checks for overlap with your library, your sources and the web."
        case .authorship: return "Records where each piece of text came from, with a shareable replay."
        case .chat: return "Ask, research, rewrite and brainstorm with your document as context."
        case .resume: return "Turns your experience into a clean, one-page resume."
        }
    }
    var color: Color {
        switch self {
        case .proofreader: return Theme.color(.correctness)
        case .paraphraser, .resume: return Theme.color(.clarity)
        case .humanizer, .readerReactions: return Theme.color(.engagement)
        case .expertReview, .aiGrader, .chat: return Theme.color(.delivery)
        case .citationFinder, .authorship: return Theme.syrup
        case .aiDetector, .plagiarism: return Theme.indigo
        }
    }
    var needsAI: Bool { ![.authorship, .aiDetector].contains(self) }
}

struct AgentGrid: View {
    var columns = 2
    var onPick: (AgentKind) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(AgentKind.allCases) { a in
                Button { onPick(a) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: a.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(a.color)
                        Text(a.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(a.blurb).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(3).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .card(padding: 10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Runs one agent against an editor.
struct AgentRunnerView: View {
    let kind: AgentKind
    @ObservedObject var controller: EditorController
    var chat: ChatSession? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(kind.color)
                    .frame(width: 34, height: 34).background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text(kind.blurb).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if kind.needsAI && !AppState.shared.hasAPIKey {
                ErrorBanner(message: "This agent uses Claude. Add your API key in Settings → AI.")
            }
            switch kind {
            case .proofreader: ProofreaderAgent(controller: controller)
            case .paraphraser: ParaphraserAgent(controller: controller)
            case .humanizer: HumanizerAgent(controller: controller)
            case .expertReview: ExpertReviewAgent(controller: controller)
            case .readerReactions: ReaderReactionsAgent(controller: controller)
            case .aiGrader: GraderAgent(controller: controller)
            case .citationFinder: CitationFinderAgent(controller: controller)
            case .aiDetector: AIDetectorAgent(controller: controller)
            case .plagiarism: PlagiarismAgent(controller: controller)
            case .authorship: AuthorshipAgent(controller: controller)
            case .chat:
                ChatView(session: chat ?? ChatSession(),
                         contextProvider: { (controller.text, controller.title.isEmpty ? "your document" : controller.title) },
                         insertAction: { controller.insert($0, origin: .ai) }, compact: true)
                    .frame(minHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .resume: ResumeAgent(controller: controller)
            }
        }
    }
}

// MARK: - Shared helpers

/// Small state machine every agent uses: idle → working → done/error.
@MainActor
final class AgentTask<Output>: ObservableObject {
    @Published var output: Output?
    @Published var working = false
    @Published var error: String?

    func run(_ work: @escaping (WafflezAI) async throws -> Output) {
        working = true
        error = nil
        Task { @MainActor in
            do {
                let ai = try AppState.shared.ai()
                output = try await work(ai)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

struct EditRow: View {
    var edit: AIEdit
    var onApply: () -> Void
    var onLocate: (() -> Void)? = nil
    @State private var applied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CategoryDot(category: edit.category, size: 7)
                Text(edit.explanation).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(edit.original).font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary).strikethrough(true, color: Theme.danger.opacity(0.6)).lineLimit(4)
            Text(edit.replacement).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(6)
            HStack {
                Button(applied ? "Applied" : "Apply") { onApply(); applied = true }
                    .buttonStyle(GhostButtonStyle(tint: applied ? Theme.textTertiary : Theme.success)).disabled(applied)
                if let onLocate { Button("Show") { onLocate() }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

func runButton(_ title: String, working: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        if working { WorkingView(label: "Working…") } else { Label(title, systemImage: "sparkles") }
    }
    .buttonStyle(PrimaryButtonStyle())
    .disabled(working)
}

// MARK: - Proofreader

struct ProofreaderAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<[AIEdit]>()
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            runButton("Proofread document", working: task.working) {
                let text = controller.text
                let goals = controller.goals
                let dialect = state.settings.dialect
                task.run { try await $0.proofread(text, goals: goals, dialect: dialect) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            if let edits = task.output {
                HStack {
                    Text("\(edits.count) edits").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Underline in document") { controller.setAIEdits(edits, ruleID: "proofreader") }.buttonStyle(GhostButtonStyle())
                    Button("Apply all") { for e in edits { controller.apply(edit: e, origin: .wafflez) } }.buttonStyle(GhostButtonStyle(tint: Theme.success))
                }
                ForEach(edits) { e in
                    EditRow(edit: e, onApply: { controller.apply(edit: e, origin: .wafflez) }, onLocate: {
                        let r = (controller.text as NSString).range(of: e.original)
                        if r.location != NSNotFound { controller.highlight(r) }
                    })
                }
            }
        }
    }
}

// MARK: - Paraphraser

struct ParaphraserAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<String>()
    @ObservedObject var state = AppState.shared
    @State private var style: ParaphraseStyle = .standard
    @State private var scopeSelection = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Style", selection: $style) { ForEach(ParaphraseStyle.allCases) { Text($0.displayName).tag($0) } }
            if style == .customVoice {
                Text("Your voice sample (saved in Settings → AI):").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                TextArea(text: $state.settings.voiceSample, placeholder: "Paste a few paragraphs you wrote yourself so Wafflez can learn your voice.", minHeight: 80)
            }
            Toggle("Only the selected text", isOn: $scopeSelection).toggleStyle(.checkbox).font(.system(size: 12))
            runButton("Paraphrase", working: task.working) {
                let useSel = scopeSelection && !controller.selectedText.isEmpty
                let text = useSel ? controller.selectedText : controller.text
                let st = style, sample = state.settings.voiceSample, dialect = state.settings.dialect
                task.run { try await $0.paraphrase(text, style: st, voiceSample: sample, dialect: dialect) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            if let out = task.output {
                Text(out).font(.system(size: 13)).foregroundStyle(Theme.text).textSelection(.enabled).card(padding: 10)
                HStack {
                    if scopeSelection && !controller.selectedText.isEmpty {
                        Button("Replace selection") { controller.replaceSelection(out, origin: .ai) }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Replace document") { controller.replaceAll(out, origin: .ai) }.buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Insert at cursor") { controller.insert(out, origin: .ai) }.buttonStyle(GhostButtonStyle())
                    Button("Copy") { copyToClipboard(out) }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}

// MARK: - Humanizer

struct HumanizerAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<HumanizeResult>()
    @ObservedObject var state = AppState.shared
    @State private var voice: HumanizeVoice = .natural
    @State private var local: [HumanizeChange]?

    var body: some View {
        let before = AIDetector().analyze(controller.text)
        VStack(alignment: .leading, spacing: 10) {
            if before.enoughText {
                HStack {
                    Image(systemName: "cpu").foregroundStyle(Theme.indigo)
                    Text("AI-like now: \(before.percent)%").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("(on-device estimate)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            Picker("Voice", selection: $voice) { ForEach(HumanizeVoice.allCases) { Text($0.displayName).tag($0) } }
            Text(voice.guidance).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if voice == .myVoice && state.settings.voiceSample.trimmed.isEmpty {
                TextArea(text: $state.settings.voiceSample, placeholder: "Paste something you wrote so Wafflez can match your voice.", minHeight: 70)
            }
            HStack {
                runButton("Humanize with AI", working: task.working) {
                    let text = controller.selectedText.isEmpty ? controller.text : controller.selectedText
                    let v = voice, sample = state.settings.voiceSample, dialect = state.settings.dialect
                    task.run { try await $0.humanize(text, voice: v, voiceSample: sample, dialect: dialect) }
                }
                Button("Quick pass (offline)") { local = LocalHumanizer().suggestions(for: controller.text) }.buttonStyle(GhostButtonStyle())
            }
            if let error = task.error { ErrorBanner(message: error) }

            if let local {
                Text(local.isEmpty ? "No stock phrases found." : "\(local.count) quick changes").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                if !local.isEmpty {
                    Button("Apply all quick changes") {
                        controller.replaceAll(LocalHumanizer().humanize(controller.text), origin: .wafflez)
                        self.local = nil
                    }.buttonStyle(GhostButtonStyle(tint: Theme.success))
                }
                ForEach(local) { c in
                    EditRow(edit: AIEdit(original: c.original, replacement: c.replacement, category: .engagement, explanation: c.reason),
                            onApply: { controller.apply(edit: AIEdit(original: c.original, replacement: c.replacement, category: .engagement, explanation: ""), origin: .wafflez) })
                }
            }

            if let out = task.output {
                let after = AIDetector().analyze(out.rewrite)
                if after.enoughText && before.enoughText {
                    Text("Estimated AI-like: \(before.percent)% → \(after.percent)%").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.success)
                }
                HStack {
                    if controller.selectedText.isEmpty {
                        Button("Replace document") { controller.replaceAll(out.rewrite, origin: .ai) }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Replace selection") { controller.replaceSelection(out.rewrite, origin: .ai) }.buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Copy") { copyToClipboard(out.rewrite) }.buttonStyle(GhostButtonStyle())
                }
                Text("Or apply one sentence at a time:").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                ForEach(out.changes) { e in EditRow(edit: e, onApply: { controller.apply(edit: e) }) }
            }
            Text("Use this to polish your own drafts. Passing off someone else's work as your own isn't something any tool can make right.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Expert Review

struct ExpertReviewAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<[ExpertTip]>()
    @State private var field = ""
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Subject (e.g. marine biology, product marketing)", text: $field).textFieldStyle(.roundedBorder)
            runButton("Get expert feedback", working: task.working) {
                let text = controller.text, f = field, goals = controller.goals
                task.run { try await $0.expertReview(text, field: f, goals: goals) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            ForEach(task.output ?? []) { tip in
                VStack(alignment: .leading, spacing: 6) {
                    Text(tip.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(tip.feedback).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if expanded.contains(tip.id) {
                        Text(tip.example).font(.system(size: 12.5)).italic().foregroundStyle(Theme.text)
                            .padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        Button(expanded.contains(tip.id) ? "Hide example" : "Show example") {
                            if expanded.contains(tip.id) { expanded.remove(tip.id) } else { expanded.insert(tip.id) }
                        }.buttonStyle(GhostButtonStyle())
                        Button("Insert example") { controller.insert(tip.example, origin: .ai) }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                    }
                }
                .card(padding: 10)
            }
        }
    }
}

// MARK: - Reader Reactions

struct ReaderReactionsAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<ReaderReaction>()
    @State private var persona: ReaderPersona = .manager
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Reader", selection: $persona) { ForEach(ReaderPersona.allCases) { Text($0.displayName).tag($0) } }
            if persona == .custom {
                TextField("Describe your reader (e.g. a skeptical CFO who hates jargon)", text: $custom).textFieldStyle(.roundedBorder)
            }
            runButton("Predict reactions", working: task.working) {
                let text = controller.text, p = persona, c = custom
                task.run { try await $0.readerReactions(text, persona: p, customReader: c) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            if let r = task.output {
                section("Overall", [r.overall])
                section("They'll take away", [r.takeaway])
                section("They'll ask", r.questions)
                section("They might misunderstand", r.misunderstandings)
                if !r.fixes.isEmpty {
                    Text("Suggested fixes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    ForEach(r.fixes) { e in EditRow(edit: e, onApply: { controller.apply(edit: e) }) }
                }
            }
        }
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            ForEach(items, id: \.self) { Text("• " + $0).font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

// MARK: - AI Grader

struct GraderAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<GradeReport>()
    @State private var rubric = ""
    @State private var course = ""
    @State private var uploadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rubric").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Upload rubric…") { upload() }.buttonStyle(GhostButtonStyle())
            }
            TextArea(text: $rubric, placeholder: "Paste the rubric or assignment criteria…", minHeight: 90)
            if let uploadError { ErrorBanner(message: uploadError) }
            TextField("Course details (e.g. ENGL 101, argumentative essay, 1500 words)", text: $course).textFieldStyle(.roundedBorder)
            runButton("Grade my draft", working: task.working) {
                let text = controller.text, r = rubric, c = course
                task.run { try await $0.grade(text, rubric: r, courseDetails: c) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            if let g = task.output {
                HStack(alignment: .firstTextBaseline) {
                    Text(g.estimatedGrade).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.syrup)
                    Text("estimated").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Text(g.summary).font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                ForEach(g.criteria) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(c.name).font(.system(size: 12.5, weight: .semibold)); Spacer(); Text(c.score).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.syrup) }
                            .foregroundStyle(Theme.text)
                        Text(c.feedback).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .card(padding: 10)
                }
                if !g.improvements.isEmpty {
                    Text("To raise your grade").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    ForEach(g.improvements, id: \.self) { Text("• " + $0).font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
                }
                Text("An estimate to help you revise — not an official grade.").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let text = DocumentImport.text(from: url) { rubric = text; uploadError = nil } else { uploadError = "Couldn't read that file." }
    }
}

enum DocumentImport {
    static func text(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return PDFDocument(url: url)?.string }
        if ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm"].contains(ext) {
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func attributed(from url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let s = PDFDocument(url: url)?.string { return NSAttributedString(string: s, attributes: Theme.editorAttributes) }
        if ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm"].contains(ext) {
            return try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
        if let s = try? String(contentsOf: url, encoding: .utf8) { return NSAttributedString(string: s, attributes: Theme.editorAttributes) }
        return nil
    }
}

// MARK: - Citation Finder

struct CitationFinderAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<[CitationFinding]>()
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Style", selection: $state.settings.citationStyle) { ForEach(CitationStyle.allCases) { Text($0.fullName).tag($0) } }
            runButton("Find sources (searches the web)", working: task.working) {
                let text = controller.text, style = state.settings.citationStyle
                task.run { try await $0.findCitations(text, style: style) }
            }
            if let error = task.error { ErrorBanner(message: error) }
            if let findings = task.output {
                if findings.isEmpty { Text("No claims needing sources were found.").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary) }
                ForEach(findings) { f in
                    let style = state.settings.citationStyle
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(f.supports ? "SUPPORTS" : "DISPUTES").font(.system(size: 10, weight: .bold)).tracking(0.5)
                                .foregroundStyle(f.supports ? Theme.success : Theme.danger)
                            Spacer()
                        }
                        Text("“\(f.claim)”").font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary).lineLimit(3)
                        Text(CitationFormatter.bibliography(f.source, style: style)).font(.system(size: 12.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                        if !f.note.isEmpty { Text(f.note).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary) }
                        HStack {
                            Button("Insert in-text citation") { insertInText(f, style: style) }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                            Button("Add to references") { addReference(f, style: style) }.buttonStyle(GhostButtonStyle())
                            if let url = URL(string: f.source.url) { Link("Open", destination: url).font(.system(size: 12)) }
                        }
                    }
                    .card(padding: 10)
                }
                Text("Sources come from a live web search. Open each one to confirm it says what you need before you cite it.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Theme.stroke)
            CitationGeneratorView(onInsert: { controller.insert($0, origin: .wafflez) })
        }
    }

    private func insertInText(_ f: CitationFinding, style: CitationStyle) {
        guard let tv = controller.textView else { return }
        let ns = tv.string as NSString
        let r = ns.range(of: f.claim)
        let cite = " " + CitationFormatter.inText(f.source, style: style)
        if r.location != NSNotFound {
            var end = r.location + r.length
            // Put the citation before the sentence's final punctuation.
            if end > 0, end <= ns.length, ".!?".contains(ns.substring(with: NSRange(location: end - 1, length: 1))) { end -= 1 }
            tv.replace(NSRange(location: end, length: 0), with: cite, origin: .wafflez)
        } else {
            controller.insert(cite, origin: .wafflez)
        }
    }

    private func addReference(_ f: CitationFinding, style: CitationStyle) {
        guard let tv = controller.textView else { return }
        let marker = style == .mla ? "Works Cited" : (style == .apa ? "References" : "Bibliography")
        let entry = CitationFormatter.bibliography(f.source, style: style)
        let len = (tv.string as NSString).length
        tv.replace(NSRange(location: len, length: 0), with: tv.string.contains("\n\(marker)\n") ? "\n\(entry)" : "\n\n\(marker)\n\(entry)", origin: .wafflez)
    }
}

/// Free citation generator: fill in the details, get a formatted citation.
struct CitationGeneratorView: View {
    var onInsert: (String) -> Void
    @ObservedObject var state = AppState.shared
    @State private var source = CitationSource()
    @State private var authors = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Citation generator").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Picker("Type", selection: $source.kind) { ForEach(SourceKind.allCases) { Text($0.displayName).tag($0) } }
            TextField("Authors (comma-separated, First Last)", text: $authors).textFieldStyle(.roundedBorder)
            TextField("Title", text: $source.title).textFieldStyle(.roundedBorder)
            TextField(source.kind == .journal ? "Journal" : "Website or publication", text: $source.container).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Year", text: $source.year).textFieldStyle(.roundedBorder).frame(width: 70)
                TextField("Month", text: $source.month).textFieldStyle(.roundedBorder)
                TextField("Day", text: $source.day).textFieldStyle(.roundedBorder).frame(width: 50)
            }
            if source.kind == .journal {
                HStack {
                    TextField("Volume", text: $source.volume).textFieldStyle(.roundedBorder)
                    TextField("Issue", text: $source.issue).textFieldStyle(.roundedBorder)
                    TextField("Pages", text: $source.pages).textFieldStyle(.roundedBorder)
                }
            }
            if source.kind == .book { TextField("Publisher", text: $source.publisher).textFieldStyle(.roundedBorder) }
            TextField("URL", text: $source.url).textFieldStyle(.roundedBorder)
            let s = filled
            let bib = CitationFormatter.bibliography(s, style: state.settings.citationStyle)
            if !source.title.isEmpty {
                Text(bib).font(.system(size: 12.5)).foregroundStyle(Theme.text).textSelection(.enabled).card(padding: 10)
                HStack {
                    Button("Insert") { onInsert(bib) }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                    Button("Copy") { copyToClipboard(bib) }.buttonStyle(GhostButtonStyle())
                    Text(CitationFormatter.inText(s, style: state.settings.citationStyle)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var filled: CitationSource {
        var s = source
        s.authors = authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !s.url.isEmpty { s.accessed = Date() }
        return s
    }
}

// MARK: - AI Detector

struct AIDetectorAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var opinion = AgentTask<AIDetectionOpinion>()
    @State private var report: AIDetectionReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { report = AIDetector().analyze(controller.text) } label: { Label("Check for AI-like writing", systemImage: "cpu") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Second opinion from Claude") {
                    let text = controller.text
                    opinion.run { try await $0.aiDetectionOpinion(text) }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(opinion.working)
            }
            if let r = report {
                if r.enoughText {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle().stroke(Theme.raised, lineWidth: 7)
                            Circle().trim(from: 0, to: CGFloat(r.percent) / 100).stroke(Theme.indigo, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text("\(r.percent)%").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                        }
                        .frame(width: 66, height: 66)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(r.percent)% appears AI-generated").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(r.verdict).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(r.signals, id: \.self) { Text("• " + $0).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    if !r.flagged.isEmpty {
                        HStack {
                            Text("\(r.flagged.count) flagged sentence\(r.flagged.count == 1 ? "" : "s")").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Button("Highlight in document") { controller.markedRanges = r.flagged.map(\.range) }.buttonStyle(GhostButtonStyle())
                        }
                        ForEach(r.flagged) { s in
                            Button { controller.highlight(s.range) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.text).font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(4).multilineTextAlignment(.leading)
                                    ForEach(s.reasons, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Theme.indigo) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(padding: 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text(r.verdict).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            if opinion.working { WorkingView(label: "Asking Claude…") }
            if let e = opinion.error { ErrorBanner(message: e) }
            if let o = opinion.output {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude's estimate: \(o.percent)%").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(o.rationale).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 10)
            }
            Text("This is an estimate, not proof. No detector can tell for certain who wrote something, and other schools' or companies' detectors may disagree. For proof of how you wrote, use Authorship.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Plagiarism

struct PlagiarismAgent: View {
    @ObservedObject var controller: EditorController
    @ObservedObject var state = AppState.shared
    @StateObject private var web = AgentTask<[WebMatch]>()
    @State private var report: OriginalityReport?
    @State private var extraSources: [SourceDocument] = []
    @State private var rewriting: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { checkLocal() } label: { Label("Check against my library", systemImage: "books.vertical") }.buttonStyle(PrimaryButtonStyle())
                Button("Add source files…") { addSources() }.buttonStyle(GhostButtonStyle())
            }
            if !extraSources.isEmpty {
                Text("\(extraSources.count) extra source file\(extraSources.count == 1 ? "" : "s") added").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
            if let r = report {
                HStack(spacing: 10) {
                    Text("\(r.originalPercent)% original").font(.system(size: 15, weight: .bold)).foregroundStyle(r.matchedPercent > 15 ? Theme.danger : Theme.success)
                    Text("compared with \(state.documents.count - 1 + extraSources.count) documents").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                ForEach(r.matches) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(m.sourceTitle).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text); Spacer(); Text("\(m.percent)%").foregroundStyle(Theme.danger).font(.system(size: 12.5, weight: .bold)) }
                        Text("“\(m.excerpt)”").font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary).lineLimit(4)
                        HStack {
                            Button("Highlight") { controller.markedRanges = m.passages.map(\.range) }.buttonStyle(GhostButtonStyle())
                            if let first = m.passages.first { Button("Rewrite passage") { rewrite(first.range) }.buttonStyle(GhostButtonStyle(tint: Theme.indigo)) }
                        }
                    }
                    .card(padding: 10)
                }
            }
            Divider().overlay(Theme.stroke)
            runButton("Search the web for matches", working: web.working) {
                let text = controller.text
                web.run { try await $0.webOriginality(text) }
            }
            if let e = web.error { ErrorBanner(message: e) }
            if let matches = web.output {
                if matches.isEmpty { Text("No matching pages found on the web.").font(.system(size: 12.5)).foregroundStyle(Theme.success) }
                ForEach(matches) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.sourceTitle).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(m.note).font(.system(size: 11.5)).foregroundStyle(Theme.danger)
                        Text("“\(m.passage)”").font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary).lineLimit(4)
                        HStack {
                            Button("Show in document") {
                                let r = (controller.text as NSString).range(of: m.passage)
                                if r.location != NSNotFound { controller.markedRanges = [r]; controller.highlight(r) }
                            }.buttonStyle(GhostButtonStyle())
                            Button("Cite this source") {
                                var s = CitationSource(); s.title = m.sourceTitle; s.url = m.url; s.accessed = Date()
                                let entry = CitationFormatter.bibliography(s, style: state.settings.citationStyle)
                                controller.insert(" " + CitationFormatter.inText(s, style: state.settings.citationStyle), origin: .wafflez)
                                copyToClipboard(entry)
                            }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                            if let url = URL(string: m.url) { Link("Open", destination: url).font(.system(size: 12)) }
                        }
                    }
                    .card(padding: 10)
                }
            }
            if let rewriting { WorkingView(label: rewriting) }
            Text("Library checks run on your Mac. Web checks use Claude's web search on your most distinctive sentences; they can miss paywalled or unindexed sources.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkLocal() {
        let mine = controller.documentID
        let library = state.documents.filter { $0.id != mine }.map { SourceDocument(title: $0.title, text: $0.plainText) }
        report = OriginalityChecker().check(controller.text, against: library + extraSources)
    }

    private func addSources() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .html, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let t = DocumentImport.text(from: url) { extraSources.append(SourceDocument(title: url.lastPathComponent, text: t)) }
        }
    }

    private func rewrite(_ range: NSRange) {
        let ns = controller.text as NSString
        guard range.location + range.length <= ns.length else { return }
        let passage = ns.substring(with: range)
        rewriting = "Rewriting in your own words…"
        Task { @MainActor in
            defer { rewriting = nil }
            guard let ai = try? state.ai(), let out = try? await ai.paraphrase(passage, style: .standard, voiceSample: state.settings.voiceSample, dialect: state.settings.dialect) else { return }
            controller.apply(edit: AIEdit(original: passage, replacement: out, category: .clarity, explanation: ""))
        }
    }
}

// MARK: - Authorship

struct AuthorshipAgent: View {
    @ObservedObject var controller: EditorController
    @State private var replayStep: Double = 0
    @State private var showReplay = false

    var body: some View {
        let ledger = controller.ledger
        VStack(alignment: .leading, spacing: 10) {
            if ledger.isRecording {
                Label("Recording — every edit is labeled by where it came from.", systemImage: "record.circle")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.success)
            } else {
                Text("Turn on Authorship before you start writing. It can only vouch for text written while it's on.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button { controller.startAuthorship() } label: { Label("Turn on Authorship", systemImage: "touchid") }.buttonStyle(PrimaryButtonStyle())
            }
            if !ledger.runs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    let shares = Dictionary(uniqueKeysWithValues: ledger.percentages().map { ($0.0, $0.1) })
                    ForEach(TextOrigin.allCases.filter { shares[$0] != nil }) { origin in
                        let pct = shares[origin] ?? 0
                        HStack(spacing: 8) {
                            Circle().fill(Theme.color(origin)).frame(width: 8, height: 8)
                            Text(origin.displayName).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(String(format: "%.0f%%", pct)).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.raised).overlay(alignment: .leading) {
                                Capsule().fill(Theme.color(origin)).frame(width: g.size.width * pct / 100)
                            }
                        }.frame(height: 6)
                    }
                }
                .card(padding: 10)
                Toggle("Color the document by origin", isOn: $controller.showAuthorship).toggleStyle(.switch).font(.system(size: 12.5))
                HStack {
                    Button("Replay") { replayStep = Double(ledger.events.count); showReplay = true }.buttonStyle(GhostButtonStyle())
                    Button("Export report…") { export() }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                    Button("Open report") { openReport() }.buttonStyle(GhostButtonStyle())
                    if ledger.isRecording { Button("Stop") { controller.stopAuthorship() }.buttonStyle(GhostButtonStyle(tint: Theme.danger)) }
                }
                Text("The report is a single web page anyone can open without an account. Share the file, or upload it to your class portal. Delete the file to unshare.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Authorship records your writing process. It isn't an AI detector.").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
        }
        .sheet(isPresented: $showReplay) { replaySheet(ledger) }
    }

    private func replaySheet(_ ledger: AuthorshipLedger) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Replay").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Done") { showReplay = false }.buttonStyle(PrimaryButtonStyle())
            }
            Slider(value: $replayStep, in: 0...Double(max(1, ledger.events.count)), step: 1)
            Text("Step \(Int(replayStep)) of \(ledger.events.count)").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            ScrollView {
                Text(ledger.replay(events: Int(replayStep))).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(10)
            .background(Theme.midnight, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(Theme.surface)
        .environment(\.colorScheme, .dark)
    }

    private var reportHTML: String {
        AuthorshipReport.html(title: controller.title.isEmpty ? "Untitled" : controller.title, text: controller.text, ledger: controller.ledger)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(controller.title.isEmpty ? "Document" : controller.title) - Authorship.html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? reportHTML.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openReport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wafflez-authorship-\(UUID().uuidString.prefix(8)).html")
        try? reportHTML.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Resume Builder

struct ResumeAgent: View {
    @ObservedObject var controller: EditorController
    @StateObject private var task = AgentTask<String>()
    @State private var details = ""
    @State private var role = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Target role (e.g. Junior UX designer)", text: $role).textFieldStyle(.roundedBorder)
            TextArea(text: $details, placeholder: "Your experience, education, skills and achievements — rough notes are fine.", minHeight: 140)
            runButton("Build resume", working: task.working) {
                let d = details.isEmpty ? controller.text : details, r = role
                task.run { try await $0.resume(from: d, targetRole: r) }
            }
            if let e = task.error { ErrorBanner(message: e) }
            if let out = task.output {
                Text(out).font(.system(size: 12.5, design: .default)).foregroundStyle(Theme.text).textSelection(.enabled).card(padding: 10)
                HStack {
                    Button("Insert into document") { controller.insert(out, origin: .ai) }.buttonStyle(PrimaryButtonStyle())
                    Button("Save as new document") {
                        let d = AppState.shared.newDocument(title: role.isEmpty ? "Resume" : "Resume — \(role)", text: out)
                        StudioWindow.shared.open(document: d.id)
                    }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}
