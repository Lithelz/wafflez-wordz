import Foundation

// MARK: - Categories (underline colors)

/// The five suggestion categories. Each one has its own underline color.
public enum IssueCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case correctness
    case clarity
    case engagement
    case delivery
    case styleGuide

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .correctness: return "Correctness"
        case .clarity: return "Clarity"
        case .engagement: return "Engagement"
        case .delivery: return "Delivery"
        case .styleGuide: return "Style guide"
        }
    }

    public var blurb: String {
        switch self {
        case .correctness: return "Spelling, grammar and punctuation"
        case .clarity: return "Wordy or hard-to-read sentences"
        case .engagement: return "Bland or repeated words"
        case .delivery: return "Tone, formality, politeness, confidence and inclusive language"
        case .styleGuide: return "Your team's custom writing rules"
        }
    }

    /// Underline color as hex. Tuned to read well on a midnight background.
    public var hexColor: String {
        switch self {
        case .correctness: return "#FF6B81"
        case .clarity: return "#5AA9FF"
        case .engagement: return "#3DDC97"
        case .delivery: return "#B58CFF"
        case .styleGuide: return "#9AA3C7"
        }
    }

    /// Lower number wins when two suggestions overlap.
    public var priority: Int {
        switch self {
        case .correctness: return 0
        case .styleGuide: return 1
        case .clarity: return 2
        case .delivery: return 3
        case .engagement: return 4
        }
    }

    /// Weight used by the overall score.
    var scoreWeight: Double {
        switch self {
        case .correctness: return 6
        case .clarity: return 3
        case .engagement: return 1.5
        case .delivery: return 2.5
        case .styleGuide: return 2
        }
    }
}

// MARK: - Suggestion

/// One fix for one underline. Ranges are UTF-16 offsets (NSString / NSTextView / Accessibility API units).
public struct Suggestion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var ruleID: String
    public var category: IssueCategory
    public var location: Int
    public var length: Int
    public var original: String
    public var replacements: [String]
    public var title: String
    public var explanation: String
    public var learnMore: String?
    public var isSpelling: Bool
    /// Clarity cards for long sentences can offer an AI rewrite instead of a fixed replacement.
    public var offersAIRewrite: Bool

    public init(
        ruleID: String,
        category: IssueCategory,
        range: NSRange,
        original: String,
        replacements: [String],
        title: String,
        explanation: String,
        learnMore: String? = nil,
        isSpelling: Bool = false,
        offersAIRewrite: Bool = false
    ) {
        self.id = UUID()
        self.ruleID = ruleID
        self.category = category
        self.location = range.location
        self.length = range.length
        self.original = original
        self.replacements = replacements
        self.title = title
        self.explanation = explanation
        self.learnMore = learnMore
        self.isSpelling = isSpelling
        self.offersAIRewrite = offersAIRewrite
    }

    public var range: NSRange { NSRange(location: location, length: length) }
    public var end: Int { location + length }

    public func overlaps(_ other: Suggestion) -> Bool {
        location < other.end && other.location < end
    }

    /// Moves this suggestion after an edit elsewhere in the text. Returns nil if the edit touched it.
    public func shifted(afterEditAt editRange: NSRange, insertedLength: Int) -> Suggestion? {
        let delta = insertedLength - editRange.length
        if end <= editRange.location { return self }
        if location >= editRange.location + editRange.length {
            var copy = self
            copy.location += delta
            return copy
        }
        return nil
    }
}

// MARK: - Settings that shape checking

public enum Dialect: String, Codable, CaseIterable, Identifiable, Sendable {
    case american, british, canadian, australian, indian
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .american: return "American English"
        case .british: return "British English"
        case .canadian: return "Canadian English"
        case .australian: return "Australian English"
        case .indian: return "Indian English"
        }
    }
    /// Language code for the macOS spell checker.
    public var spellLanguage: String {
        switch self {
        case .american: return "en_US"
        case .british: return "en_GB"
        case .canadian: return "en_CA"
        case .australian: return "en_AU"
        case .indian: return "en_IN"
        }
    }
}

public enum Formality: String, Codable, CaseIterable, Identifiable, Sendable {
    case informal, neutral, formal
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum Audience: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, knowledgeable, expert
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum Domain: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, academic, business, email, technical, creative, casual
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum Intent: String, Codable, CaseIterable, Identifiable, Sendable {
    case inform, describe, convince, tellAStory
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .inform: return "Inform"
        case .describe: return "Describe"
        case .convince: return "Convince"
        case .tellAStory: return "Tell a story"
        }
    }
}

public struct WritingGoals: Codable, Hashable, Sendable {
    public var audience: Audience = .general
    public var formality: Formality = .neutral
    public var domain: Domain = .general
    public var intent: Intent = .inform
    public init() {}
}

// MARK: - Team features

/// A style guide rule: a term your team avoids and what to write instead. Shown as gray underlines.
public struct StyleRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var term: String
    public var replacement: String
    public var note: String
    public var caseSensitive: Bool = false
    public var enabled: Bool = true
    public init(term: String, replacement: String, note: String = "", caseSensitive: Bool = false) {
        self.term = term
        self.replacement = replacement
        self.note = note
        self.caseSensitive = caseSensitive
    }
}

/// A brand tone: the voice your writing should lean toward.
public struct BrandTone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var summary: String
    public var traits: [String]
    public var wordsToAvoid: [String]
    public var enabled: Bool = true
    public init(name: String, summary: String, traits: [String], wordsToAvoid: [String]) {
        self.name = name
        self.summary = summary
        self.traits = traits
        self.wordsToAvoid = wordsToAvoid
    }
}

/// A saved block of text you can drop into any message.
public struct Snippet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var shortcut: String
    public var body: String
    public init(name: String, shortcut: String, body: String) {
        self.name = name
        self.shortcut = shortcut
        self.body = body
    }
}

/// Knowledge Share: a company term or acronym and what it means.
public struct GlossaryTerm: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var term: String
    public var definition: String
    public init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }
}

/// Everything the checker needs to know about the writer's preferences.
public struct AnalyzerConfig: Codable, Hashable, Sendable {
    public var dialect: Dialect = .american
    public var goals: WritingGoals = WritingGoals()
    public var disabledRules: Set<String> = []
    public var disabledCategories: Set<IssueCategory> = []
    public var personalDictionary: Set<String> = []
    public var styleRules: [StyleRule] = []
    public var brandTones: [BrandTone] = []
    public var maxSentenceWords: Int = 35
    public var checkSpelling: Bool = true
    public init() {}

    public func allows(_ ruleID: String, _ category: IssueCategory) -> Bool {
        !disabledRules.contains(ruleID) && !disabledCategories.contains(category)
    }
}

/// Every rule a user can turn off on the preferences page.
public struct RuleInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var category: IssueCategory
    public var summary: String
}

public enum RuleCatalog {
    public static let all: [RuleInfo] = [
        RuleInfo(id: "spelling", name: "Spelling", category: .correctness, summary: "Misspelled words"),
        RuleInfo(id: "grammar-system", name: "Grammar (macOS)", category: .correctness, summary: "Grammar issues found by the built-in macOS checker"),
        RuleInfo(id: "repeated-word", name: "Repeated words", category: .correctness, summary: "\"the the\""),
        RuleInfo(id: "a-an", name: "A vs. an", category: .correctness, summary: "\"a apple\" → \"an apple\""),
        RuleInfo(id: "lowercase-i", name: "Lowercase \"i\"", category: .correctness, summary: "\"i think\" → \"I think\""),
        RuleInfo(id: "sentence-case", name: "Sentence capitalization", category: .correctness, summary: "Capitalize the first word of a sentence"),
        RuleInfo(id: "spacing", name: "Spacing", category: .correctness, summary: "Double spaces and spaces before punctuation"),
        RuleInfo(id: "missing-apostrophe", name: "Missing apostrophes", category: .correctness, summary: "\"dont\" → \"don't\""),
        RuleInfo(id: "confused-words", name: "Commonly confused words", category: .correctness, summary: "its/it's, then/than, your/you're and more"),
        RuleInfo(id: "oxford-comma", name: "Oxford comma", category: .correctness, summary: "\"red, white and blue\" → \"red, white, and blue\""),
        RuleInfo(id: "dialect-spelling", name: "Dialect spelling", category: .correctness, summary: "color/colour, organize/organise to match your English"),
        RuleInfo(id: "wordy", name: "Wordy phrases", category: .clarity, summary: "\"in order to\" → \"to\""),
        RuleInfo(id: "filler", name: "Filler words", category: .clarity, summary: "basically, actually, literally"),
        RuleInfo(id: "passive-voice", name: "Passive voice", category: .clarity, summary: "\"was written by\" → active voice"),
        RuleInfo(id: "long-sentence", name: "Long sentences", category: .clarity, summary: "Sentences that are hard to follow"),
        RuleInfo(id: "intensifier", name: "Weak intensifiers", category: .engagement, summary: "\"very good\" → \"excellent\""),
        RuleInfo(id: "bland-word", name: "Bland words", category: .engagement, summary: "Overused words like good, nice, thing"),
        RuleInfo(id: "repetition", name: "Repeated vocabulary", category: .engagement, summary: "The same word used again and again"),
        RuleInfo(id: "hedging", name: "Confidence", category: .delivery, summary: "Hedging like \"I think\" or \"just wanted to\""),
        RuleInfo(id: "formality", name: "Formality", category: .delivery, summary: "Slang and casual words when writing formally"),
        RuleInfo(id: "politeness", name: "Politeness", category: .delivery, summary: "Demands that may read as rude"),
        RuleInfo(id: "inclusive", name: "Inclusive language", category: .delivery, summary: "Terms that could exclude or offend"),
        RuleInfo(id: "brand-tone", name: "Brand tone", category: .delivery, summary: "Words your brand tone avoids"),
        RuleInfo(id: "style-guide", name: "Style guide", category: .styleGuide, summary: "Your team's custom rules"),
    ]
}
