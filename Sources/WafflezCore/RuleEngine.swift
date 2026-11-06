import Foundation

// MARK: - Spelling hook

/// Spelling and system grammar come from the platform (NSSpellChecker on macOS).
/// The engine only depends on this protocol so it stays testable anywhere.
public protocol SpellingProvider: Sendable {
    func misspellings(in text: String, language: String) -> [(range: NSRange, guesses: [String])]
    func grammarIssues(in text: String, language: String) -> [(range: NSRange, message: String, fixes: [String])]
}

public struct NoSpellingProvider: SpellingProvider {
    public init() {}
    public func misspellings(in text: String, language: String) -> [(range: NSRange, guesses: [String])] { [] }
    public func grammarIssues(in text: String, language: String) -> [(range: NSRange, message: String, fixes: [String])] { [] }
}

// MARK: - Rule plumbing

public final class RuleContext {
    public let text: String
    public let ns: NSString
    public let config: AnalyzerConfig
    public private(set) lazy var sentences: [SentenceSpan] = TextUtils.sentences(in: text)
    public private(set) lazy var words: [WordSpan] = TextUtils.words(in: text)

    public init(text: String, config: AnalyzerConfig) {
        self.text = text
        self.ns = text as NSString
        self.config = config
    }

    public func sub(_ r: NSRange) -> String { ns.substring(with: r) }

    /// True if the range sits inside a URL, email, @mention, #tag or `code`.
    public func isInsideNonProse(_ r: NSRange) -> Bool {
        nonProseRanges.contains { NSIntersectionRange($0, r).length > 0 }
    }

    private lazy var nonProseRanges: [NSRange] = {
        let re = NSRegularExpression.ci("(https?://\\S+|www\\.\\S+|\\S+@\\S+\\.\\S+|[@#][\\w.-]+|`[^`]*`)")
        return re.allMatches(text).map { $0.range }
    }()
}

public protocol WritingRule {
    var id: String { get }
    var category: IssueCategory { get }
    func check(_ ctx: RuleContext) -> [Suggestion]
}

/// A data-driven rule: one regex per phrase, with fixed replacements.
public struct PhraseRule: WritingRule {
    public struct Entry {
        let regex: NSRegularExpression
        let replacements: [String]
        let title: String
        let explanation: String
        /// When true, deleting the phrase also removes one neighbouring space.
        let isDeletion: Bool
    }

    public let id: String
    public let category: IssueCategory
    let entries: [Entry]
    let learnMore: String?
    let condition: (AnalyzerConfig) -> Bool

    public init(id: String, category: IssueCategory, learnMore: String? = nil,
                when condition: @escaping (AnalyzerConfig) -> Bool = { _ in true },
                entries: [(String, [String], String, String)]) {
        self.id = id
        self.category = category
        self.learnMore = learnMore
        self.condition = condition
        self.entries = entries.map { item in
            let (pattern, reps, title, why) = item
            let isDeletion = reps.count == 1 && reps[0].isEmpty
            // Whole-word match that also works when the phrase starts or ends with punctuation.
            let full = "(?<![A-Za-z'’])(?:" + pattern + ")(?![A-Za-z])"
            return Entry(regex: .ci(full), replacements: reps, title: title, explanation: why, isDeletion: isDeletion)
        }
    }

    public func check(_ ctx: RuleContext) -> [Suggestion] {
        guard condition(ctx.config) else { return [] }
        var out: [Suggestion] = []
        for entry in entries {
            for m in entry.regex.allMatches(ctx.text) {
                var range = m.range
                if ctx.isInsideNonProse(range) { continue }
                let original = ctx.sub(range)
                var reps: [String]
                if entry.isDeletion {
                    // Remove the phrase and one adjacent space so no double space is left behind.
                    let after = range.location + range.length
                    if after < ctx.ns.length, ctx.ns.character(at: after) == 32 {
                        range.length += 1
                    } else if range.location > 0, ctx.ns.character(at: range.location - 1) == 32 {
                        range.location -= 1
                        range.length += 1
                    }
                    reps = [""]
                } else {
                    reps = entry.replacements.map { rep in
                        let expanded = m.numberOfRanges > 1 ? expand(rep, match: m, in: ctx) : rep
                        return TextUtils.matchCase(original, expanded)
                    }
                }
                out.append(Suggestion(
                    ruleID: id, category: category, range: range,
                    original: ctx.sub(range), replacements: reps,
                    title: entry.title, explanation: entry.explanation, learnMore: learnMore
                ))
            }
        }
        return out
    }

    private func expand(_ template: String, match: NSTextCheckingResult, in ctx: RuleContext) -> String {
        var result = template
        for g in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            let r = match.range(at: g)
            let value = r.location == NSNotFound ? "" : ctx.sub(r)
            result = result.replacingOccurrences(of: "$\(g)", with: value)
        }
        return result
    }
}

// MARK: - Results

public struct TextStats: Codable, Hashable, Sendable {
    public var characters: Int = 0
    public var charactersNoSpaces: Int = 0
    public var words: Int = 0
    public var sentences: Int = 0
    public var paragraphs: Int = 0
    public var averageSentenceLength: Double = 0
    public var averageWordLength: Double = 0
    public var readingTimeSeconds: Int = 0
    public var speakingTimeSeconds: Int = 0
    public var fleschReadingEase: Double = 0
    public var uniqueWordRatio: Double = 0

    public var readabilityLabel: String {
        switch fleschReadingEase {
        case 80...: return "Very easy to read"
        case 65..<80: return "Easy to read"
        case 50..<65: return "Fairly easy to read"
        case 30..<50: return "Hard to read"
        default: return "Very hard to read"
        }
    }
}

public struct AnalysisResult: Sendable {
    public var text: String
    public var suggestions: [Suggestion]
    public var stats: TextStats
    public var tone: ToneResult?
    public var score: Int

    public func count(_ category: IssueCategory) -> Int {
        suggestions.filter { $0.category == category }.count
    }

    public static let empty = AnalysisResult(text: "", suggestions: [], stats: TextStats(), tone: nil, score: 100)
}

// MARK: - Analyzer

public final class TextAnalyzer: @unchecked Sendable {
    public let spelling: SpellingProvider
    private let rules: [WritingRule]
    private let toneDetector = ToneDetector()

    public init(spelling: SpellingProvider = NoSpellingProvider()) {
        self.spelling = spelling
        self.rules = CorrectnessRules.all + ClarityRules.all + EngagementRules.all + DeliveryRules.all
            + [DialectRule(), StyleGuideRule(), BrandToneRule()]
    }

    public func analyze(_ text: String, config: AnalyzerConfig, includeTone: Bool = true) -> AnalysisResult {
        let ctx = RuleContext(text: text, config: config)
        var found: [Suggestion] = []

        if config.checkSpelling, config.allows("spelling", .correctness) {
            found += spellingSuggestions(ctx)
        }
        if config.allows("grammar-system", .correctness) {
            for g in spelling.grammarIssues(in: text, language: config.dialect.spellLanguage) {
                guard g.range.location + g.range.length <= ctx.ns.length, !ctx.isInsideNonProse(g.range) else { continue }
                found.append(Suggestion(
                    ruleID: "grammar-system", category: .correctness, range: g.range,
                    original: ctx.sub(g.range), replacements: g.fixes,
                    title: "Grammar", explanation: g.message
                ))
            }
        }
        for rule in rules where config.allows(rule.id, rule.category) {
            found += rule.check(ctx)
        }

        let suggestions = Self.resolveOverlaps(found)
        let stats = Self.stats(for: ctx)
        let tone = includeTone ? toneDetector.detect(text) : nil
        return AnalysisResult(
            text: text, suggestions: suggestions, stats: stats, tone: tone,
            score: Self.score(suggestions: suggestions, stats: stats)
        )
    }

    private func spellingSuggestions(_ ctx: RuleContext) -> [Suggestion] {
        let dictionary = Set(ctx.config.personalDictionary.map { $0.lowercased() })
        let glossary = Set(ctx.config.styleRules.map { $0.replacement.lowercased() })
        var out: [Suggestion] = []
        for miss in spelling.misspellings(in: ctx.text, language: ctx.config.dialect.spellLanguage) {
            let r = miss.range
            guard r.location + r.length <= ctx.ns.length, !ctx.isInsideNonProse(r) else { continue }
            let word = ctx.sub(r)
            let lower = word.lowercased()
            if dictionary.contains(lower) || glossary.contains(lower) { continue }
            // Skip code-like tokens: camelCase, digits, underscores, ALLCAPS acronyms.
            if word.contains(where: { $0.isNumber || $0 == "_" }) { continue }
            if word.count > 1, word == word.uppercased() { continue }
            if word.dropFirst().contains(where: { $0.isUppercase }) { continue }
            out.append(Suggestion(
                ruleID: "spelling", category: .correctness, range: r, original: word,
                replacements: Array(miss.guesses.prefix(4)),
                title: miss.guesses.isEmpty ? "Unknown word" : "Correct the spelling",
                explanation: miss.guesses.isEmpty
                    ? "\"\(word)\" isn't in the dictionary. If it's spelled right, add it to your dictionary."
                    : "\"\(word)\" may be misspelled.",
                isSpelling: true
            ))
        }
        return out
    }

    /// Keeps the higher-priority suggestion when two overlap, so underlines never stack.
    static func resolveOverlaps(_ items: [Suggestion]) -> [Suggestion] {
        let ordered = items.sorted {
            if $0.category.priority != $1.category.priority { return $0.category.priority < $1.category.priority }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.location < $1.location
        }
        var kept: [Suggestion] = []
        var sentenceLevel: [Suggestion] = []
        for s in ordered where s.length > 0 {
            // Whole-sentence hints (long sentences) live alongside word-level fixes.
            if s.ruleID == "long-sentence" { sentenceLevel.append(s); continue }
            if !kept.contains(where: { $0.overlaps(s) }) { kept.append(s) }
        }
        kept += sentenceLevel
        return kept.sorted { $0.location < $1.location }
    }

    static func stats(for ctx: RuleContext) -> TextStats {
        var s = TextStats()
        let text = ctx.text
        s.characters = text.count
        s.charactersNoSpaces = text.filter { !$0.isWhitespace }.count
        let words = ctx.words
        s.words = words.count
        s.sentences = max(ctx.sentences.count, words.isEmpty ? 0 : 1)
        s.paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        guard !words.isEmpty else { return s }
        s.averageSentenceLength = Double(s.words) / Double(max(1, s.sentences))
        s.averageWordLength = Double(words.reduce(0) { $0 + $1.text.count }) / Double(words.count)
        s.readingTimeSeconds = Int((Double(s.words) / 238.0 * 60).rounded())
        s.speakingTimeSeconds = Int((Double(s.words) / 183.0 * 60).rounded())
        let syllables = words.reduce(0) { $0 + TextUtils.syllables($1.text) }
        let fre = 206.835 - 1.015 * s.averageSentenceLength - 84.6 * (Double(syllables) / Double(words.count))
        s.fleschReadingEase = min(100, max(0, fre))
        s.uniqueWordRatio = Double(Set(words.map { $0.lower }).count) / Double(words.count)
        return s
    }

    /// 0–100. Starts at 100 and loses points per issue, scaled to text length.
    public static func score(suggestions: [Suggestion], stats: TextStats) -> Int {
        guard stats.words > 0 else { return 100 }
        let penalty = suggestions.filter { $0.ruleID != "long-sentence" }.reduce(0.0) { $0 + $1.category.scoreWeight }
            + Double(suggestions.filter { $0.ruleID == "long-sentence" }.count) * 1.5
        // Short messages are measured as if they were 80 words long, so one slip doesn't sink the score.
        let per100 = penalty / max(80, Double(stats.words)) * 100
        var score = 100 - per100 * 1.2
        if stats.fleschReadingEase < 30 { score -= 4 }
        return Int(min(100, max(0, score)).rounded())
    }
}
