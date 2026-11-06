import SwiftUI
import WafflezCore

/// Text the user selected in another app, and how to put a result back.
struct SelectionContext {
    var text: String
    var appName: String
    /// Replaces the selection with new text.
    var replace: (String) -> Void
    var close: () -> Void
}

// MARK: - Highlight to rewrite / Translate / Explain / Ask

struct SelectionAssistantView: View {
    let context: SelectionContext
    @ObservedObject var state = AppState.shared

    enum Mode: Equatable { case menu, working(String), result(String, replaces: Bool), error(String) }
    @State private var mode: Mode = .menu
    @State private var custom = ""
    @State private var question = ""
    @State private var language = UserDefaults.standard.string(forKey: "wz.translate.language") ?? "Spanish"
    @State private var lastAction: (() -> Void)?

    private let quick: [RewriteMode] = [.improve, .shorten, .professional, .friendly, .confident, .simplify, .fixGrammar, .expand]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WaffleMark(size: 18)
                Text("Wafflez AI").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("· \(context.text.split(separator: " ").count) words selected").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button { context.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            switch mode {
            case .menu: menu
            case .working(let label): WorkingView(label: label).padding(.vertical, 8)
            case .result(let text, let replaces): result(text, replaces: replaces)
            case .error(let message):
                ErrorBanner(message: message)
                Button("Back") { mode = .menu }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .panelChrome()
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(quick) { m in
                    Button { rewrite(m) } label: { Label(m.displayName, systemImage: m.symbol) }
                        .buttonStyle(ChipButtonStyle())
                }
                Button { humanize() } label: { Label("Humanize", systemImage: "person.wave.2") }.buttonStyle(ChipButtonStyle())
                Button { explain() } label: { Label("Explain", systemImage: "text.magnifyingglass") }.buttonStyle(ChipButtonStyle())
            }
            HStack(spacing: 6) {
                Image(systemName: "globe").foregroundStyle(Theme.textSecondary)
                Picker("", selection: $language) {
                    ForEach(WafflezAI.languages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                Button("Translate") { translate() }.buttonStyle(GhostButtonStyle())
            }
            inputRow(icon: "wand.and.stars", placeholder: "Revise with AI: tell it what to change…", text: $custom) { revise() }
            inputRow(icon: "questionmark.bubble", placeholder: "Ask about this text…", text: $question) { ask() }
            if !state.hasAPIKey {
                Text("Add your Claude API key in Wafflez Studio → Settings → AI to use these.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.syrup)
            }
        }
    }

    private func inputRow(icon: String, placeholder: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.indigo)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(submit)
            Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)) }
                .buttonStyle(.plain).foregroundStyle(text.wrappedValue.trimmed.isEmpty ? Theme.textTertiary : Theme.syrup)
                .disabled(text.wrappedValue.trimmed.isEmpty)
        }
        .padding(8)
        .background(Theme.midnight.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func result(_ text: String, replaces: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                if replaces {
                    Button("Accept") { context.replace(text) }.buttonStyle(PrimaryButtonStyle())
                }
                Button("Retry") { lastAction?() }.buttonStyle(GhostButtonStyle())
                Button("Copy") { copyToClipboard(text) }.buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Back") { mode = .menu }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
            }
        }
    }

    private func run(_ label: String, replaces: Bool, _ work: @escaping (WafflezAI) async throws -> String) {
        let action = { run(label, replaces: replaces, work) }
        lastAction = action
        mode = .working(label)
        Task { @MainActor in
            do {
                let ai = try state.ai()
                let out = try await work(ai)
                mode = .result(out, replaces: replaces)
            } catch {
                mode = .error(error.localizedDescription)
            }
        }
    }

    private func rewrite(_ m: RewriteMode) {
        let s = state.settings
        run("Rewriting…", replaces: true) { try await $0.rewrite(context.text, mode: m, goals: s.goals, dialect: s.dialect, brand: s.activeBrandTone) }
    }
    private func humanize() {
        let s = state.settings
        run("Humanizing…", replaces: true) { try await $0.humanize(context.text, voice: .natural, voiceSample: s.voiceSample, dialect: s.dialect).rewrite }
    }
    private func explain() { run("Explaining…", replaces: false) { try await $0.explain(context.text) } }
    private func translate() {
        UserDefaults.standard.set(language, forKey: "wz.translate.language")
        let lang = language
        run("Translating…", replaces: true) { try await $0.translate(context.text, to: lang) }
    }
    private func revise() {
        let instruction = custom
        let s = state.settings
        run("Revising…", replaces: true) { try await $0.revise(context.text, instruction: instruction, goals: s.goals, dialect: s.dialect) }
    }
    private func ask() {
        let q = question
        run("Reading…", replaces: false) { try await $0.ask(q, about: context.text) }
    }
}

// MARK: - Lightbulb compose + Reply quickly

struct ComposeView: View {
    var screenContext: () -> String
    var insert: (String) -> Void
    var close: () -> Void
    var startInReplyMode = false
    @ObservedObject var state = AppState.shared

    @State private var prompt = ""
    @State private var useScreen = true
    @State private var output: String?
    @State private var working: String?
    @State private var error: String?
    @State private var replyIdeas: ReplyIdeas?
    @State private var lastRun: (() -> Void)?
    @FocusState private var focused: Bool

    private let ideas = ["Write a reply", "Draft an email about…", "Make an outline", "Brainstorm ideas", "Summarize this page", "Write a LinkedIn post"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Theme.success)
                Text("Write with AI").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Toggle("Use what's on screen", isOn: $useScreen).toggleStyle(.checkbox).font(.system(size: 11.5))
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            if output == nil && working == nil && replyIdeas == nil {
                FlowLayout(spacing: 6) {
                    Button { replyQuickly() } label: { Label("Reply quickly", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(ChipButtonStyle())
                    ForEach(ideas, id: \.self) { idea in
                        Button(idea) { prompt = idea.replacingOccurrences(of: "…", with: " "); focused = true }
                            .buttonStyle(ChipButtonStyle())
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("Tell Wafflez what to write…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(generate)
                Button(action: generate) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(prompt.trimmed.isEmpty ? Theme.textTertiary : Theme.syrup)
                    .disabled(prompt.trimmed.isEmpty)
            }
            .padding(9)
            .background(Theme.midnight.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))

            if let working { WorkingView(label: working) }
            if let error { ErrorBanner(message: error) }
            if let replyIdeas, output == nil, working == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(replyIdeas.summary).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(replyIdeas.ideas) { idea in
                        Button { writeReply(idea) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(idea.gist).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let output {
                ScrollView {
                    Text(output).font(.system(size: 13.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                HStack {
                    Button("Insert") { insert(output) }.buttonStyle(PrimaryButtonStyle())
                    Button("Retry") { lastRun?() }.buttonStyle(GhostButtonStyle())
                    Button("Copy") { copyToClipboard(output) }.buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button("New") { self.output = nil; replyIdeas = nil; prompt = "" }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                }
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .panelChrome()
        .onAppear {
            focused = true
            if startInReplyMode { replyQuickly() }
        }
    }

    private func generate() {
        let request = prompt.trimmed
        guard !request.isEmpty else { return }
        let context = useScreen ? screenContext() : nil
        let s = state.settings
        lastRun = { generate() }
        working = "Writing…"; error = nil; output = nil
        Task { @MainActor in
            do {
                output = try await state.ai().compose(request, context: context, goals: s.goals, dialect: s.dialect, brand: s.activeBrandTone)
            } catch { self.error = error.localizedDescription }
            working = nil
        }
    }

    private func replyQuickly() {
        let email = screenContext()
        guard !email.trimmed.isEmpty else { error = "Couldn't read an email on screen. Open the message you're replying to."; return }
        working = "Reading the email…"; error = nil; output = nil
        Task { @MainActor in
            do { replyIdeas = try await state.ai().replyIdeas(to: email) } catch { self.error = error.localizedDescription }
            working = nil
        }
    }

    private func writeReply(_ idea: ReplyIdea) {
        let email = screenContext()
        let s = state.settings
        lastRun = { writeReply(idea) }
        working = "Writing your reply…"; error = nil
        Task { @MainActor in
            do { output = try await state.ai().writeReply(to: email, idea: idea, signature: s.signature, goals: s.goals) }
            catch { self.error = error.localizedDescription }
            working = nil
        }
    }
}

// MARK: - Definitions and synonyms

struct DefinitionView: View {
    var word: String
    var definition: String?
    var canReplace: Bool
    var sentence: String
    var replace: (String) -> Void
    var close: () -> Void
    @ObservedObject var state = AppState.shared
    @State private var more: [String] = []
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(word).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            if let definition {
                Text(definition).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(8)
            } else {
                Text("No definition found in the macOS dictionary.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            let syns = Array(Set(Definitions.localSynonyms(word) + more)).sorted()
            if canReplace {
                if !syns.isEmpty {
                    Text("SYNONYMS").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textTertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(syns, id: \.self) { s in
                            Button(TextUtils.matchCase(word, s)) { replace(TextUtils.matchCase(word, s)) }.buttonStyle(ChipButtonStyle())
                        }
                    }
                }
                if working { WorkingView(label: "Finding words…") }
                else if more.isEmpty {
                    Button { findMore() } label: { Label("More synonyms with AI", systemImage: "sparkles") }
                        .buttonStyle(GhostButtonStyle(tint: Theme.indigo))
                }
                if let error { ErrorBanner(message: error) }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .panelChrome()
    }

    private func findMore() {
        working = true
        Task { @MainActor in
            do { more = try await state.ai().synonyms(for: word, in: sentence) } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

// MARK: - Snippets picker

struct SnippetPickerView: View {
    var insert: (String) -> Void
    var close: () -> Void
    @ObservedObject var state = AppState.shared
    @State private var query = ""
    @FocusState private var focused: Bool

    var filtered: [Snippet] {
        let q = query.lowercased().trimmed
        guard !q.isEmpty else { return state.settings.snippets }
        return state.settings.snippets.filter { $0.name.lowercased().contains(q) || $0.shortcut.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.badge.plus").foregroundStyle(Theme.syrup)
                TextField("Search snippets…", text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let first = filtered.first { insert(first.body) } }
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            Divider().overlay(Theme.stroke)
            if filtered.isEmpty {
                Text("No snippets yet. Add them in Wafflez Studio → Snippets.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(filtered.prefix(8)) { s in
                Button { insert(s.body) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            if !s.shortcut.isEmpty { Text("\\\(s.shortcut)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.syrup) }
                        }
                        Text(s.body).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .panelChrome()
        .onAppear { focused = true }
    }
}
