import SwiftUI
import WafflezCore

private struct ScreenScaffold<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.horizontal, 28).padding(.top, 38).padding(.bottom, 28)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}

// MARK: - Style guide

struct StyleGuideScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var term = ""
    @State private var replacement = ""
    @State private var note = ""
    @State private var caseSensitive = false

    var body: some View {
        ScreenScaffold(title: "Style guide", subtitle: "Your team's writing rules. When someone breaks one, Wafflez shows a gray underline with your preferred wording.") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Avoid (e.g. e-mail)", text: $term).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(Theme.textTertiary)
                    TextField("Use instead (e.g. email)", text: $replacement).textFieldStyle(.roundedBorder)
                }
                HStack {
                    TextField("Why (optional, shown on the card)", text: $note).textFieldStyle(.roundedBorder)
                    Toggle("Match case", isOn: $caseSensitive).toggleStyle(.checkbox)
                    Button("Add rule") {
                        state.settings.styleRules.append(StyleRule(term: term.trimmed, replacement: replacement.trimmed, note: note.trimmed, caseSensitive: caseSensitive))
                        term = ""; replacement = ""; note = ""
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(term.trimmed.isEmpty)
                }
            }
            .card()
            ForEach($state.settings.styleRules) { $rule in
                HStack(spacing: 10) {
                    Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    CategoryDot(category: .styleGuide)
                    Text(rule.term).strikethrough().foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    Text(rule.replacement.isEmpty ? "(flag only)" : rule.replacement).fontWeight(.semibold).foregroundStyle(Theme.text)
                    if !rule.note.isEmpty { Text("· " + rule.note).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).lineLimit(1) }
                    Spacer()
                    Button { state.settings.styleRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                }
                .font(.system(size: 13))
                .card(padding: 10)
            }
        }
    }
}

// MARK: - Brand tones

struct BrandTonesScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var name = ""
    @State private var summary = ""
    @State private var traits = ""
    @State private var avoid = ""

    var body: some View {
        ScreenScaffold(title: "Brand tones", subtitle: "Define your company voice. The active tone shapes every AI rewrite and flags words your brand avoids.") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name (e.g. Warm & clear)", text: $name).textFieldStyle(.roundedBorder)
                TextField("Describe the voice in a sentence or two", text: $summary).textFieldStyle(.roundedBorder)
                TextField("Traits, comma-separated (friendly, confident, concise)", text: $traits).textFieldStyle(.roundedBorder)
                TextField("Words to avoid, comma-separated", text: $avoid).textFieldStyle(.roundedBorder)
                Button("Add brand tone") {
                    state.settings.brandTones.append(BrandTone(name: name.trimmed, summary: summary.trimmed,
                                                               traits: split(traits), wordsToAvoid: split(avoid)))
                    name = ""; summary = ""; traits = ""; avoid = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmed.isEmpty)
            }
            .card()
            ForEach(state.settings.brandTones) { tone in
                let active = state.settings.activeBrandToneID == tone.id
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tone.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        if active { Text("ACTIVE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.syrup) }
                        Spacer()
                        Button(active ? "Turn off" : "Make active") {
                            state.settings.activeBrandToneID = active ? nil : tone.id
                        }
                        .buttonStyle(GhostButtonStyle(tint: active ? Theme.textSecondary : Theme.syrup))
                        Button { state.settings.brandTones.removeAll { $0.id == tone.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                    }
                    Text(tone.summary).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    if !tone.traits.isEmpty { Text("Traits: " + tone.traits.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.text) }
                    if !tone.wordsToAvoid.isEmpty { Text("Avoid: " + tone.wordsToAvoid.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.danger) }
                }
                .card()
            }
        }
    }

    private func split(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Snippets

struct SnippetsScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var name = ""
    @State private var shortcut = ""
    @State private var body_ = ""

    var body: some View {
        ScreenScaffold(title: "Snippets", subtitle: "Saved blocks of text you can drop into any app with \(state.settings.hotKey(.snippets).display), or with /snippet in the Studio.") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    TextField("Shortcut (e.g. thx)", text: $shortcut).textFieldStyle(.roundedBorder).frame(width: 160)
                }
                TextArea(text: $body_, placeholder: "Snippet text…", minHeight: 80)
                Button("Add snippet") {
                    state.settings.snippets.append(Snippet(name: name.trimmed, shortcut: shortcut.trimmed, body: body_))
                    name = ""; shortcut = ""; body_ = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmed.isEmpty || body_.trimmed.isEmpty)
            }
            .card()
            ForEach($state.settings.snippets) { $snip in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name", text: $snip.name).textFieldStyle(.plain).font(.system(size: 13.5, weight: .semibold))
                        Text("\\").foregroundStyle(Theme.syrup)
                        TextField("shortcut", text: $snip.shortcut).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.syrup).frame(width: 110)
                        Spacer()
                        Button { copyToClipboard(snip.body) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                        Button { state.settings.snippets.removeAll { $0.id == snip.id } } label: { Image(systemName: "trash") }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                    }
                    TextArea(text: $snip.body, placeholder: "", minHeight: 60)
                }
                .card()
            }
        }
    }
}

// MARK: - Knowledge Share

struct KnowledgeScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var term = ""
    @State private var definition = ""
    @State private var query = ""

    var body: some View {
        ScreenScaffold(title: "Knowledge Share", subtitle: "Company terms and acronyms. Wafflez won't flag them as misspellings, and AI tools use them as context.") {
            HStack {
                TextField("Term or acronym", text: $term).textFieldStyle(.roundedBorder).frame(width: 200)
                TextField("What it means", text: $definition).textFieldStyle(.roundedBorder)
                Button("Add") {
                    state.settings.glossary.append(GlossaryTerm(term: term.trimmed, definition: definition.trimmed))
                    state.addToDictionary(term.trimmed)
                    term = ""; definition = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(term.trimmed.isEmpty || definition.trimmed.isEmpty)
            }
            .card()
            TextField("Search terms", text: $query).textFieldStyle(.roundedBorder)
            ForEach(state.settings.glossary.filter { query.isEmpty || $0.term.localizedCaseInsensitiveContains(query) || $0.definition.localizedCaseInsensitiveContains(query) }) { g in
                HStack(alignment: .top) {
                    Text(g.term).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.syrup).frame(width: 140, alignment: .leading)
                    Text(g.definition).font(.system(size: 13)).foregroundStyle(Theme.text)
                    Spacer()
                    Button { state.settings.glossary.removeAll { $0.id == g.id } } label: { Image(systemName: "trash") }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                }
                .card(padding: 10)
            }
        }
    }
}

// MARK: - Dictionary

struct DictionaryScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var word = ""
    var body: some View {
        ScreenScaffold(title: "Dictionary", subtitle: "Words you've added are never flagged as misspellings, in any app.") {
            HStack {
                TextField("Add a word", text: $word).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).buttonStyle(PrimaryButtonStyle()).disabled(word.trimmed.isEmpty)
            }
            .card()
            if state.settings.personalDictionary.isEmpty {
                Text("No words yet. Click the book icon on a spelling card to add one.").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(state.settings.personalDictionary.sorted(), id: \.self) { w in
                    HStack(spacing: 4) {
                        Text(w)
                        Button { state.settings.personalDictionary.removeAll { $0 == w } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.raised, in: Capsule())
                }
            }
        }
    }
    private func add() { state.addToDictionary(word); word = "" }
}
