import AppKit
import SwiftUI
import WafflezCore

struct SettingsScreen: View {
    @ObservedObject var state = AppState.shared
    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", suggestions = "Suggestions", ai = "AI", shortcuts = "Shortcuts", apps = "Block list", privacy = "Privacy"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Settings").padding(.horizontal, 28).padding(.top, 38)
            Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 28).padding(.vertical, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .general: GeneralSettings()
                    case .suggestions: SuggestionSettings()
                    case .ai: AISettings()
                    case .shortcuts: ShortcutSettings()
                    case .apps: BlockListSettings()
                    case .privacy: PrivacySettings()
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }
}

private struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }
}

struct GeneralSettings: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(title: "Accessibility permission",
                       detail: state.accessibilityTrusted ? "Granted. Wafflez can check text in other apps." : "Needed to read and fix text in other apps. Your text stays on your Mac.") {
                if state.accessibilityTrusted {
                    Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    Button("Grant access") { AX.requestTrust(); AX.openAccessibilitySettings() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            Divider().overlay(Theme.stroke)
            SettingRow(title: "Check writing in every app", detail: "Underlines, the widget and cards in Mail, Messages, Notes, Word, browsers and more.") {
                Toggle("", isOn: $state.settings.everywhereEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Show the Wafflez tab", detail: "A tab on the right edge of the screen that opens suggestions, chat and tone. Underlines keep working when it's off.") {
                Toggle("", isOn: $state.settings.sideTabEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Rewrite bar on selected text", detail: "A blue bar appears beside text you select. Click it to rewrite, translate, explain or ask.") {
                Toggle("", isOn: $state.settings.selectionAssistantEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Definitions and synonyms", detail: "Double-click a word to see its meaning, and replacement words when you're editing.") {
                Toggle("", isOn: $state.settings.definitionsEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Detect tone in my writing", detail: "Shows an emoji with how your message may sound once you've written \(ToneDetector.minimumCharacters) characters.") {
                Toggle("", isOn: $state.settings.toneDetectorEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Auto-citations", detail: "When you paste from a web page into the Studio, offer to add a citation.") {
                Toggle("", isOn: $state.settings.autoCitations).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Turn on Authorship for new documents", detail: "Records where text comes from in new Studio documents.") {
                Toggle("", isOn: $state.settings.authorshipByDefault).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Open at login", detail: nil) {
                Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch)
            }
            Divider().overlay(Theme.stroke)
            SettingRow(title: "I write in", detail: "Spelling follows this English.") {
                Picker("", selection: $state.settings.dialect) { ForEach(Dialect.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().frame(width: 200)
            }
            SettingRow(title: "Default goals", detail: "Used in other apps and for new documents.") {
                EmptyView()
            }
            GoalsView(goals: $state.settings.goals).card()
        }
        .card()
    }
}

struct SuggestionSettings: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Categories").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                ForEach(IssueCategory.allCases) { c in
                    SettingRow(title: c.displayName, detail: c.blurb) {
                        Toggle("", isOn: Binding(
                            get: { !state.settings.disabledCategories.contains(c) },
                            set: { on in if on { state.settings.disabledCategories.remove(c) } else { state.settings.disabledCategories.insert(c) } }
                        )).labelsHidden().toggleStyle(.switch).tint(Theme.color(c))
                    }
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestion types").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Switch off the kinds of suggestions you don't want, like Oxford commas or passive voice.").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                ForEach(RuleCatalog.all) { r in
                    HStack {
                        CategoryDot(category: r.category, size: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Text(r.summary).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !state.settings.disabledRules.contains(r.id) },
                            set: { on in if on { state.settings.disabledRules.remove(r.id) } else { state.settings.disabledRules.insert(r.id) } }
                        )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 6) {
                SettingRow(title: "Flag sentences longer than", detail: "\(state.settings.maxSentenceWords) words") {
                    Slider(value: Binding(get: { Double(state.settings.maxSentenceWords) }, set: { state.settings.maxSentenceWords = Int($0) }), in: 20...60, step: 1)
                        .frame(width: 200)
                }
            }
            .card()
        }
    }
}

struct AISettings: View {
    @ObservedObject var state = AppState.shared
    @State private var keyDraft = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Claude API key").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("AI features (rewrites, chat, agents, humanizer, citation finder) use Claude with your own key. Get one at console.anthropic.com. It's stored in your macOS Keychain — never in a file — and only sent to Anthropic.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if state.hasAPIKey {
                    HStack {
                        Label("Key saved in Keychain", systemImage: "key.fill").foregroundStyle(Theme.success)
                        Spacer()
                        Button(testing ? "Testing…" : "Test") { test() }.buttonStyle(GhostButtonStyle()).disabled(testing)
                        Button("Remove") { state.setAPIKey(nil); testResult = nil }.buttonStyle(GhostButtonStyle(tint: Theme.danger))
                    }
                } else {
                    HStack {
                        SecureField("Paste your API key", text: $keyDraft).textFieldStyle(.roundedBorder)
                        Button("Save") { state.setAPIKey(keyDraft); keyDraft = "" }.buttonStyle(PrimaryButtonStyle()).disabled(keyDraft.trimmed.isEmpty)
                    }
                }
                if let testResult { Text(testResult).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
            }
            .card()
            VStack(alignment: .leading, spacing: 4) {
                SettingRow(title: "Model", detail: "Opus gives the best quality. Sonnet and Haiku are faster and cost less.") {
                    Picker("", selection: $state.settings.model) { ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().frame(width: 260)
                }
                SettingRow(title: "AI features", detail: "Turn off for confidential mode: nothing leaves your Mac, and only on-device checks run.") {
                    Toggle("", isOn: $state.settings.aiEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Monthly AI prompt limit", detail: state.settings.monthlyPromptCap == 0 ? "No limit" : "\(state.settings.monthlyPromptCap) prompts per month") {
                    Stepper(value: $state.settings.monthlyPromptCap, in: 0...100_000, step: 100) {
                        Text(state.settings.monthlyPromptCap == 0 ? "Off" : "\(state.settings.monthlyPromptCap)").frame(width: 60)
                    }
                }
                SettingRow(title: "Used this month", detail: "\(state.insights.promptsToday) today") {
                    Text("\(state.insights.promptsThisMonth) prompts").foregroundStyle(Theme.textSecondary)
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                Text("Your voice").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("A sample of your own writing. The Paraphraser and Humanizer use it for \"My voice\".").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                TextArea(text: $state.settings.voiceSample, placeholder: "Paste a few paragraphs you wrote…", minHeight: 100)
                Text("Email signature for AI replies").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).padding(.top, 6)
                TextField("e.g. Sam", text: $state.settings.signature).textFieldStyle(.roundedBorder)
            }
            .card()
        }
    }

    private func test() {
        testing = true
        Task { @MainActor in
            do {
                let reply = try await state.ai().client.complete(system: "Reply with exactly: Wafflez is ready.", prompt: "Hi", maxTokens: 50, effort: .low)
                testResult = "✓ Connected. Claude says: \(reply)"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

struct ShortcutSettings: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keyboard shortcuts work everywhere. Click a shortcut, then press the new keys.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            ForEach(HotKeyAction.allCases) { a in
                SettingRow(title: a.displayName, detail: nil) {
                    ShortcutRecorder(hotKey: state.settings.hotKey(a)) { key in
                        state.settings.hotKeys[a] = key
                        AppDelegate.registerHotKeys()
                    }
                    Button("Reset") {
                        state.settings.hotKeys[a] = nil
                        AppDelegate.registerHotKeys()
                    }
                    .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                }
            }
            Divider().overlay(Theme.stroke)
            Text("Google Docs draws its text on a canvas that other apps can't read, so underlines can't appear there. Select text and press \(state.settings.hotKey(.quickCheck).display) instead — Wafflez checks it and pastes the fixed version back.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

struct BlockListSettings: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wafflez stays off in these apps.").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            if state.settings.blockList.isEmpty {
                Text("No blocked apps.").font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(state.settings.blockList, id: \.self) { id in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                        Text(FileManager.default.displayName(atPath: url.path)).foregroundStyle(Theme.text)
                    } else {
                        Text(id).foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Button("Unblock") { state.toggleBlock(id) }.buttonStyle(GhostButtonStyle())
                }
                .font(.system(size: 13))
            }
            Menu("Block a running app…") {
                ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier, !state.settings.blockList.contains(id) {
                        Button(app.localizedName ?? id) { state.toggleBlock(id) }
                    }
                }
            }
            .fixedSize()
        }
        .card()
    }
}

struct PrivacySettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Wafflez handles your writing").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            bullet("Spelling, grammar, clarity, tone, AI detection, plagiarism checks against your library, and Authorship all run on your Mac.")
            bullet("Text is sent to Anthropic's Claude API only when you use an AI feature, using your own API key. Turn AI off in Settings → AI for confidential mode.")
            bullet("Password fields are never read.")
            bullet("No analytics, tracking or accounts. Insights are stored only on this Mac.")
            bullet("Your API key lives in the macOS Keychain, not in any file.")
            Button("Show Wafflez data folder") { NSWorkspace.shared.open(Storage.folder) }.buttonStyle(GhostButtonStyle()).padding(.top, 6)
        }
        .card()
    }
    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(Theme.success)
            Text(s).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var onDone: () -> Void
    @ObservedObject var state = AppState.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                WaffleMark(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Wafflez Wordz").font(.system(size: 22, weight: .bold))
                    Text("Your writing assistant for every app on your Mac.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            step(1, "Allow Accessibility", "So Wafflez can read and fix text in other apps. Your text never leaves your Mac for these checks.") {
                if state.accessibilityTrusted {
                    Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    Button("Open System Settings") { AX.requestTrust(); AX.openAccessibilitySettings() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            step(2, "Add a Claude API key (optional)", "Turns on AI rewrites, chat, agents and the humanizer. Stored in your Keychain.") {
                if state.hasAPIKey {
                    Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    HStack {
                        SecureField("API key", text: $key).textFieldStyle(.roundedBorder).frame(width: 220)
                        Button("Save") { state.setAPIKey(key); key = "" }.buttonStyle(GhostButtonStyle()).disabled(key.trimmed.isEmpty)
                    }
                }
            }
            step(3, "Try it", "Click into any text box — Mail, Messages, Notes, Slack, a browser. In Google Docs, select text and press \(state.settings.hotKey(.quickCheck).display).") { EmptyView() }
            HStack {
                Spacer()
                Button("Start writing", action: onDone).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(Theme.surface)
        .environment(\.colorScheme, .dark)
    }

    private func step<T: View>(_ n: Int, _ title: String, _ detail: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 14, weight: .bold, design: .rounded)).frame(width: 28, height: 28)
                .background(Theme.accentGradient, in: Circle()).foregroundStyle(Color(hex: "#2A1A05"))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
        .card()
    }
}
