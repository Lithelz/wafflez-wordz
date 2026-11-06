import AppKit
import Combine
import Security
import ServiceManagement
import WafflezCore

// MARK: - Settings

struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String
}

enum HotKeyAction: String, CaseIterable, Codable, Identifiable {
    case quickCheck, compose, rewriteSelection, sidePanel, snippets, pause
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .quickCheck: return "Check selected text (works in Google Docs)"
        case .compose: return "AI compose"
        case .rewriteSelection: return "Rewrite selected text"
        case .sidePanel: return "Open the Wafflez side panel"
        case .snippets: return "Insert a snippet"
        case .pause: return "Pause or resume Wafflez"
        }
    }
    var defaultKey: HotKey {
        // Control + Option + key
        let mods: UInt32 = 0x1000 | 0x0800 // controlKey | optionKey
        switch self {
        case .quickCheck: return HotKey(keyCode: 13, carbonModifiers: mods, display: "⌃⌥W")
        case .compose: return HotKey(keyCode: 49, carbonModifiers: mods, display: "⌃⌥Space")
        case .rewriteSelection: return HotKey(keyCode: 15, carbonModifiers: mods, display: "⌃⌥R")
        case .sidePanel: return HotKey(keyCode: 8, carbonModifiers: mods, display: "⌃⌥C")
        case .snippets: return HotKey(keyCode: 1, carbonModifiers: mods, display: "⌃⌥S")
        case .pause: return HotKey(keyCode: 35, carbonModifiers: mods, display: "⌃⌥P")
        }
    }
}

struct AppSettings: Codable, Equatable {
    var dialect: Dialect = .american
    var goals = WritingGoals()
    var disabledRules: Set<String> = []
    var disabledCategories: Set<IssueCategory> = []
    var personalDictionary: [String] = ["Wafflez", "Wordz"]
    var styleRules: [StyleRule] = [
        StyleRule(term: "e-mail", replacement: "email", note: "Write \"email\" without a hyphen."),
        StyleRule(term: "Wafflez Words", replacement: "Wafflez Wordz", note: "Our product name ends in a z.", caseSensitive: true),
    ]
    var brandTones: [BrandTone] = [
        BrandTone(name: "Warm & clear", summary: "Friendly, plain-spoken and confident. Short sentences, no jargon.",
                  traits: ["friendly", "confident", "clear"], wordsToAvoid: ["synergy", "leverage", "circle back"]),
    ]
    var activeBrandToneID: UUID? = nil
    var snippets: [Snippet] = [
        Snippet(name: "Thanks", shortcut: "thx", body: "Thanks so much — I really appreciate it!"),
        Snippet(name: "Meeting follow-up", shortcut: "fu", body: "Thanks for meeting today. Here's a quick recap of what we agreed and the next steps:\n\n- \n- \n\nLet me know if I missed anything."),
    ]
    var glossary: [GlossaryTerm] = [
        GlossaryTerm(term: "ECS", definition: "Effective Communication Score — the average Wafflez score across your writing."),
    ]
    var everywhereEnabled = true
    var sideTabEnabled = true
    var definitionsEnabled = true
    var toneDetectorEnabled = true
    var selectionAssistantEnabled = true
    var autoCitations = true
    var authorshipByDefault = false
    var blockList: [String] = []
    var pausedUntil: Date? = nil
    var model: ClaudeModel = .opus
    var aiEnabled = true
    var monthlyPromptCap: Int = 0 // 0 = no cap
    var maxSentenceWords = 35
    var widgetAnchors: [String: Int] = [:]
    var hotKeys: [HotKeyAction: HotKey] = [:]
    var signature = ""
    var voiceSample = ""
    var citationStyle: CitationStyle = .apa
    var hasSeenWelcome = false

    func hotKey(_ a: HotKeyAction) -> HotKey { hotKeys[a] ?? a.defaultKey }

    var activeBrandTone: BrandTone? {
        guard let id = activeBrandToneID else { return nil }
        return brandTones.first { $0.id == id && $0.enabled }
    }
}

// MARK: - Insights

struct DayStats: Codable, Hashable, Identifiable {
    var id: String { day }
    var day: String // yyyy-MM-dd
    var wordsChecked = 0
    var accepted: [IssueCategory: Int] = [:]
    var dismissed = 0
    var aiPrompts = 0
    var scoreTotal = 0
    var scoreSamples = 0
    var averageScore: Double { scoreSamples == 0 ? 0 : Double(scoreTotal) / Double(scoreSamples) }
    var totalAccepted: Int { accepted.values.reduce(0, +) }
}

struct Insights: Codable {
    var days: [DayStats] = []
    var reports: [String] = []

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    mutating func update(_ change: (inout DayStats) -> Void) {
        let key = Self.todayKey()
        if let i = days.firstIndex(where: { $0.day == key }) {
            change(&days[i])
        } else {
            var d = DayStats(day: key)
            change(&d)
            days.append(d)
            if days.count > 400 { days.removeFirst(days.count - 400) }
        }
    }

    var promptsThisMonth: Int {
        let prefix = String(Self.todayKey().prefix(7))
        return days.filter { $0.day.hasPrefix(prefix) }.reduce(0) { $0 + $1.aiPrompts }
    }

    var promptsToday: Int { days.first { $0.day == Self.todayKey() }?.aiPrompts ?? 0 }
}

// MARK: - Documents

struct WDocument: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = "Untitled"
    var rtf = Data()
    var plainText = ""
    var created = Date()
    var modified = Date()
    var goals = WritingGoals()
    var ledger = AuthorshipLedger()

    static func == (a: WDocument, b: WDocument) -> Bool { a.id == b.id && a.modified == b.modified }
    func hash(into h: inout Hasher) { h.combine(id) }

    var attributed: NSAttributedString {
        if !rtf.isEmpty, let s = NSAttributedString(rtf: rtf, documentAttributes: nil) { return s }
        return NSAttributedString(string: plainText, attributes: Theme.editorAttributes)
    }

    var preview: String {
        let t = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Empty document" : String(t.prefix(120))
    }
}

// MARK: - Keychain (the API key lives here, never in files or source)

enum Keychain {
    static let service = "com.wafflezwordz.app"
    static let account = "claude-api-key"

    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Storage

enum Storage {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("WafflezWordz", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var documentsFolder: URL {
        let url = folder.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

// MARK: - App state

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: AppSettings {
        didSet { if settings != oldValue { scheduleSave(); onSettingsChanged?() } }
    }
    @Published var documents: [WDocument] = []
    @Published var insights: Insights
    @Published private(set) var hasAPIKey: Bool
    @Published var accessibilityTrusted = AX.isTrusted
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Called by the Everywhere controller so it can re-check text when preferences change.
    var onSettingsChanged: (() -> Void)?

    let analyzer = TextAnalyzer(spelling: MacSpellingProvider())
    private var saveWork: DispatchWorkItem?

    private init() {
        settings = Storage.load(AppSettings.self, "settings.json") ?? AppSettings()
        insights = Storage.load(Insights.self, "insights.json") ?? Insights()
        hasAPIKey = !(Keychain.read() ?? "").isEmpty
        loadDocuments()
    }

    var analyzerConfig: AnalyzerConfig {
        var c = AnalyzerConfig()
        c.dialect = settings.dialect
        c.goals = settings.goals
        c.disabledRules = settings.disabledRules
        c.disabledCategories = settings.disabledCategories
        c.personalDictionary = Set(settings.personalDictionary.map { $0.lowercased() })
        c.styleRules = settings.styleRules
        c.brandTones = settings.brandTones.filter { $0.enabled && $0.id == settings.activeBrandToneID }
        c.maxSentenceWords = settings.maxSentenceWords
        return c
    }

    func config(goals: WritingGoals) -> AnalyzerConfig {
        var c = analyzerConfig
        c.goals = goals
        return c
    }

    var isPaused: Bool {
        if let until = settings.pausedUntil { return until > Date() }
        return false
    }

    func pause(for seconds: TimeInterval?) {
        settings.pausedUntil = seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture
    }

    func resume() { settings.pausedUntil = nil }

    func isBlocked(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return settings.blockList.contains(bundleID)
    }

    func toggleBlock(_ bundleID: String) {
        if let i = settings.blockList.firstIndex(of: bundleID) { settings.blockList.remove(at: i) }
        else { settings.blockList.append(bundleID) }
    }

    func addToDictionary(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !settings.personalDictionary.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        settings.personalDictionary.append(w)
    }

    func disableRule(_ ruleID: String) { settings.disabledRules.insert(ruleID) }

    // MARK: AI

    func setAPIKey(_ key: String?) {
        if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            Keychain.delete()
        }
        hasAPIKey = !(Keychain.read() ?? "").isEmpty
    }

    /// Returns the AI service for one request and counts it toward usage. Throws a friendly error when AI is unavailable.
    func ai() throws -> WafflezAI {
        guard settings.aiEnabled else {
            throw ClaudeError.limitReached("AI features are off (Settings → AI → Confidential mode). Turn them on to use this.")
        }
        guard let key = Keychain.read(), !key.isEmpty else { throw ClaudeError.missingKey }
        if settings.monthlyPromptCap > 0 && insights.promptsThisMonth >= settings.monthlyPromptCap {
            throw ClaudeError.limitReached("You've reached your monthly limit of \(settings.monthlyPromptCap) AI prompts. Change it in Settings → AI.")
        }
        insights.update { $0.aiPrompts += 1 }
        scheduleSave()
        return WafflezAI(client: ClaudeClient(apiKey: key, model: settings.model))
    }

    // MARK: Insights

    func recordAccepted(_ category: IssueCategory) {
        insights.update { $0.accepted[category, default: 0] += 1 }
        scheduleSave()
    }

    func recordDismissed() {
        insights.update { $0.dismissed += 1 }
        scheduleSave()
    }

    func recordCheck(words: Int, score: Int) {
        guard words >= 20 else { return }
        insights.update { d in
            d.wordsChecked += words
            d.scoreTotal += score
            d.scoreSamples += 1
        }
        scheduleSave()
    }

    func report(_ suggestion: Suggestion, note: String) {
        insights.reports.append("\(Date()) [\(suggestion.ruleID)] \"\(suggestion.original)\" → \(suggestion.replacements.first ?? "") — \(note)")
        scheduleSave()
    }

    // MARK: Documents

    func loadDocuments() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Storage.documentsFolder, includingPropertiesForKeys: nil)) ?? []
        documents = urls.filter { $0.pathExtension == "json" }.compactMap {
            guard let d = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(WDocument.self, from: d)
        }.sorted { $0.modified > $1.modified }
        if documents.isEmpty {
            var welcome = WDocument()
            welcome.title = "Welcome to Wafflez Wordz"
            welcome.plainText = """
            Welcome to Wafflez Wordz! This is you're Studio, a place to write with every AI tool beside you.

            Try hovering over the underlined words. Red is for correctness, blue for clarity, green for engagement and purple for delivery. In order to see the agents, open the panel on the right. I just wanted to say that its a very good idea to try the Humanizer and the AI Detector to.

            Type /h1 on a new line and press Return to make a heading, or /table for a table. Select any text to rewrite it with AI.
            """
            welcome.rtf = (try? NSAttributedString(string: welcome.plainText, attributes: Theme.editorAttributes)
                .data(from: NSRange(location: 0, length: (welcome.plainText as NSString).length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
            save(welcome)
        }
    }

    @discardableResult
    func newDocument(title: String = "Untitled", text: String = "") -> WDocument {
        var d = WDocument()
        d.title = title
        d.plainText = text
        d.goals = settings.goals
        if settings.authorshipByDefault { d.ledger.start(with: text) }
        save(d)
        return d
    }

    func save(_ doc: WDocument) {
        var d = doc
        d.modified = Date()
        if let i = documents.firstIndex(where: { $0.id == d.id }) { documents[i] = d } else { documents.insert(d, at: 0) }
        if let data = try? JSONEncoder().encode(d) {
            try? data.write(to: Storage.documentsFolder.appendingPathComponent("\(d.id.uuidString).json"), options: .atomic)
        }
    }

    func delete(_ doc: WDocument) {
        documents.removeAll { $0.id == doc.id }
        try? FileManager.default.removeItem(at: Storage.documentsFolder.appendingPathComponent("\(doc.id.uuidString).json"))
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Storage.save(self.settings, "settings.json")
            Storage.save(self.insights, "insights.json")
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        Storage.save(settings, "settings.json")
        Storage.save(insights, "insights.json")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
