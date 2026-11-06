import Foundation

/// Green underlines: bland, weak or repeated vocabulary.
enum EngagementRules {
    static var all: [WritingRule] { [IntensifierRule(), BlandWordRule(), RepetitionRule()] }

    /// Small built-in thesaurus used for engagement suggestions.
    static let synonyms: [String: [String]] = [
        "good": ["great", "solid", "strong", "excellent"],
        "nice": ["pleasant", "lovely", "kind", "thoughtful"],
        "bad": ["poor", "weak", "harmful", "unpleasant"],
        "big": ["large", "major", "significant", "huge"],
        "small": ["minor", "compact", "slight", "modest"],
        "great": ["excellent", "outstanding", "remarkable", "superb"],
        "interesting": ["intriguing", "compelling", "fascinating", "engaging"],
        "amazing": ["remarkable", "impressive", "stunning", "extraordinary"],
        "awesome": ["impressive", "excellent", "fantastic", "superb"],
        "thing": ["item", "aspect", "detail", "point"],
        "things": ["items", "aspects", "details", "points"],
        "stuff": ["material", "items", "belongings", "gear"],
        "important": ["essential", "crucial", "key", "significant"],
        "help": ["assist", "support", "aid", "guide"],
        "show": ["demonstrate", "reveal", "display", "illustrate"],
        "use": ["apply", "employ", "rely on", "work with"],
        "make": ["create", "build", "produce", "craft"],
        "get": ["receive", "obtain", "earn", "gain"],
        "happy": ["glad", "delighted", "pleased", "cheerful"],
        "sad": ["unhappy", "downcast", "gloomy", "heartbroken"],
        "hard": ["difficult", "challenging", "tough", "demanding"],
        "easy": ["simple", "straightforward", "effortless", "painless"],
        "change": ["shift", "adjust", "revise", "transform"],
        "idea": ["concept", "notion", "plan", "proposal"],
        "problem": ["issue", "challenge", "obstacle", "difficulty"],
        "quickly": ["rapidly", "swiftly", "promptly", "fast"],
        "really": ["truly", "genuinely", "deeply", "seriously"],
        "said": ["explained", "noted", "stated", "remarked"],
        "think": ["believe", "expect", "suspect", "consider"],
        "want": ["hope", "aim", "intend", "wish"],
        "new": ["fresh", "recent", "novel", "modern"],
        "different": ["distinct", "varied", "unlike", "separate"],
        "many": ["numerous", "countless", "plenty of", "a range of"],
        "also": ["too", "as well", "in addition", "plus"],
        "work": ["effort", "job", "project", "labor"],
        "team": ["group", "crew", "squad", "staff"],
        "project": ["initiative", "effort", "plan", "venture"],
        "great deal": ["much", "plenty"],
        "improve": ["enhance", "refine", "strengthen", "boost"],
        "create": ["build", "design", "develop", "produce"],
        "provide": ["offer", "give", "supply", "share"],
        "ensure": ["make sure", "confirm", "guarantee", "secure"],
        "however": ["but", "still", "yet", "even so"],
        "example": ["instance", "case", "sample", "illustration"],
        "result": ["outcome", "effect", "consequence", "finding"],
        "people": ["folks", "everyone", "individuals", "readers"],
        "best": ["top", "finest", "strongest", "ideal"],
    ]

    /// "very X" → one vivid word.
    static let intensified: [String: [String]] = [
        "good": ["great", "excellent"], "bad": ["terrible", "awful"], "big": ["huge", "enormous"],
        "small": ["tiny", "minuscule"], "happy": ["delighted", "thrilled"], "sad": ["miserable", "heartbroken"],
        "tired": ["exhausted", "drained"], "important": ["crucial", "essential"], "interesting": ["fascinating", "captivating"],
        "hard": ["difficult", "challenging"], "difficult": ["arduous", "grueling"], "easy": ["effortless", "simple"],
        "fast": ["rapid", "swift"], "quick": ["rapid", "swift"], "slow": ["sluggish", "unhurried"],
        "old": ["ancient", "aged"], "hungry": ["starving", "ravenous"], "angry": ["furious", "livid"],
        "scared": ["terrified", "petrified"], "afraid": ["terrified", "fearful"], "beautiful": ["stunning", "gorgeous"],
        "pretty": ["lovely", "striking"], "ugly": ["hideous", "unsightly"], "cold": ["freezing", "frigid"],
        "hot": ["scorching", "sweltering"], "smart": ["brilliant", "sharp"], "clean": ["spotless", "pristine"],
        "dirty": ["filthy", "grimy"], "funny": ["hilarious", "hysterical"], "clear": ["obvious", "evident"],
        "rich": ["wealthy", "affluent"], "poor": ["destitute", "impoverished"], "boring": ["tedious", "dull"],
        "often": ["frequently", "regularly"], "quiet": ["silent", "hushed"], "loud": ["deafening", "thunderous"],
        "nice": ["lovely", "delightful"], "busy": ["swamped", "slammed"], "excited": ["thrilled", "elated"],
        "sure": ["certain", "confident"], "large": ["vast", "massive"], "strong": ["powerful", "robust"],
        "weak": ["feeble", "frail"], "bright": ["brilliant", "dazzling"], "dark": ["pitch-black", "dim"],
        "careful": ["meticulous", "cautious"], "simple": ["basic", "plain"], "good at": ["skilled at", "adept at"],
        "worried": ["anxious", "distressed"], "surprised": ["astonished", "stunned"], "upset": ["distraught", "distressed"],
        "useful": ["invaluable", "indispensable"], "helpful": ["invaluable", "supportive"], "expensive": ["costly", "pricey"],
        "cheap": ["inexpensive", "affordable"], "long": ["lengthy", "extended"], "short": ["brief", "concise"],
        "different": ["distinct", "unlike"], "special": ["exceptional", "remarkable"], "great": ["outstanding", "superb"],
    ]
}

struct IntensifierRule: WritingRule {
    let id = "intensifier"
    let category = IssueCategory.engagement
    static let re = NSRegularExpression.ci("\\b(very|really|extremely|super|so)\\s+([a-z]+)\\b")

    func check(_ ctx: RuleContext) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            let adj = ctx.sub(m.range(at: 2)).lowercased()
            guard let options = EngagementRules.intensified[adj] else { return nil }
            let intensifier = ctx.sub(m.range(at: 1)).lowercased()
            // "so good that..." is fine; only flag "so" when followed by punctuation or end.
            if intensifier == "so" {
                let after = m.range.location + m.range.length
                let rest = ctx.ns.length > after ? ctx.ns.substring(from: after).trimmingCharacters(in: .whitespaces) : ""
                if rest.lowercased().hasPrefix("that") || rest.lowercased().hasPrefix("as") { return nil }
            }
            let original = ctx.sub(m.range)
            return Suggestion(
                ruleID: id, category: category, range: m.range, original: original,
                replacements: options.map { TextUtils.matchCase(original, $0) },
                title: "Choose a more vivid word",
                explanation: "\"\(original)\" is a common phrase. A single, stronger word makes the writing more engaging.",
                learnMore: "Intensifiers like \"very\" and \"really\" often signal a weak word underneath."
            )
        }
    }
}

struct BlandWordRule: WritingRule {
    let id = "bland-word"
    let category = IssueCategory.engagement
    static let bland: Set<String> = ["good", "nice", "bad", "thing", "things", "stuff", "great", "amazing", "awesome", "interesting", "big"]

    func check(_ ctx: RuleContext) -> [Suggestion] {
        if ctx.config.goals.domain == .casual || ctx.config.goals.formality == .informal { return [] }
        var seen: [String: Int] = [:]
        var out: [Suggestion] = []
        for w in ctx.words where Self.bland.contains(w.lower) {
            seen[w.lower, default: 0] += 1
            // The first use is fine; flag repeats.
            guard seen[w.lower]! > 1, let syns = EngagementRules.synonyms[w.lower] else { continue }
            if ctx.isInsideNonProse(w.range) { continue }
            out.append(Suggestion(
                ruleID: id, category: category, range: w.range, original: w.text,
                replacements: syns.prefix(3).map { TextUtils.matchCase(w.text, $0) },
                title: "Try a fresher word",
                explanation: "\"\(w.text)\" is used often and can feel flat. A more specific word adds interest.",
                learnMore: "Specific words paint a clearer picture than general ones."
            ))
        }
        return out
    }
}

struct RepetitionRule: WritingRule {
    let id = "repetition"
    let category = IssueCategory.engagement

    func check(_ ctx: RuleContext) -> [Suggestion] {
        let words = ctx.words
        var out: [Suggestion] = []
        var lastSeen: [String: [Int]] = [:] // word → indexes in `words`
        for (i, w) in words.enumerated() {
            guard w.lower.count >= 4, !TextUtils.stopwords.contains(w.lower), !BlandWordRule.bland.contains(w.lower) else { continue }
            var list = lastSeen[w.lower, default: []].filter { i - $0 <= 60 }
            list.append(i)
            lastSeen[w.lower] = list
            // Third use within a 60-word window.
            if list.count >= 3 {
                let syns = EngagementRules.synonyms[w.lower] ?? []
                out.append(Suggestion(
                    ruleID: id, category: category, range: w.range, original: w.text,
                    replacements: syns.prefix(3).map { TextUtils.matchCase(w.text, $0) },
                    title: "Vary your word choice",
                    explanation: "\"\(w.text)\" appears \(list.count) times close together. Changing one keeps the reader engaged.",
                    learnMore: "Repetition is useful for emphasis, but too much can make writing feel monotonous."
                ))
                lastSeen[w.lower] = [i]
            }
        }
        return out
    }
}

/// The small built-in thesaurus, for the app's synonym cards.
public enum Thesaurus {
    public static func synonyms(_ word: String) -> [String] {
        let lower = word.lowercased()
        return EngagementRules.synonyms[lower] ?? EngagementRules.intensified[lower] ?? []
    }
}
