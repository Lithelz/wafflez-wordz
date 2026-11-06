import Foundation

/// Red underlines: spelling, grammar and punctuation.
enum CorrectnessRules {
    static var all: [WritingRule] {
        [RepeatedWordRule(), ArticleRule(), LowercaseIRule(), SentenceCaseRule(), SpacingRule(), OxfordCommaRule(),
         missingApostrophes, confusedWords]
    }

    static let missingApostrophes = PhraseRule(
        id: "missing-apostrophe", category: .correctness,
        learnMore: "A contraction joins two words and uses an apostrophe to show where letters were dropped: do not → don't.",
        entries: [
            ("dont", ["don't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("doesnt", ["doesn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("didnt", ["didn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("cant", ["can't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("isnt", ["isn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("arent", ["aren't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("wasnt", ["wasn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("werent", ["weren't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("couldnt", ["couldn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("wouldnt", ["wouldn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("shouldnt", ["shouldn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("havent", ["haven't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("hasnt", ["hasn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("hadnt", ["hadn't"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("youre", ["you're"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("theyre", ["they're"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("im", ["I'm"], "Add an apostrophe", "\"I'm\" is short for \"I am\" and needs an apostrophe."),
            ("ive", ["I've"], "Add an apostrophe", "\"I've\" is short for \"I have\" and needs an apostrophe."),
            ("youve", ["you've"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("theyve", ["they've"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("weve", ["we've"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("thats", ["that's"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("whats", ["what's"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("theres", ["there's"], "Add an apostrophe", "Contractions need an apostrophe."),
            ("wont(?=\\s+(?:be|have|work|go|do|let|need|happen|take|make)\\b)", ["won't"], "Add an apostrophe", "\"Won't\" is short for \"will not\"."),
        ]
    )

    static let confusedWords = PhraseRule(
        id: "confused-words", category: .correctness,
        learnMore: "Some words sound alike but mean different things. Picking the right one keeps your meaning clear.",
        entries: [
            ("(could|would|should|must|might) of", ["$1 have"], "Use \"have\", not \"of\"", "After could, would, should, must or might, use \"have\". \"Of\" only sounds the same."),
            ("alot", ["a lot"], "Split \"a lot\"", "\"A lot\" is always two words."),
            ("irregardless", ["regardless"], "Use \"regardless\"", "\"Irregardless\" is nonstandard. \"Regardless\" means the same thing."),
            ("your welcome", ["you're welcome"], "Use \"you're\"", "\"You're\" means \"you are\"."),
            ("your (going|not|being|doing|getting|right|wrong|so|very|really|gonna|welcome|the best)", ["you're $1"], "Use \"you're\"", "\"You're\" means \"you are\". \"Your\" shows ownership."),
            ("its (a|an|the|been|not|going|very|so|time|important|clear|true|likely|hard|easy|okay|ok|possible|raining|getting|my|your|our)", ["it's $1"], "Use \"it's\"", "\"It's\" means \"it is\" or \"it has\". \"Its\" shows ownership."),
            ("it's (own|self)", ["its $1"], "Use \"its\"", "\"Its\" shows ownership. \"It's\" means \"it is\"."),
            ("(more|less|better|worse|rather|bigger|smaller|greater|higher|lower|larger|faster|slower|older|younger|easier|harder|other) then", ["$1 than"], "Use \"than\" for comparisons", "Use \"than\" to compare things. \"Then\" is about time."),
            ("their (is|are|was|were|will be|has been)", ["there $1"], "Use \"there\"", "\"There\" points to a place or existence. \"Their\" shows ownership."),
            ("there (own|car|house|team|friends|work|parents)", ["their $1"], "Use \"their\"", "\"Their\" shows ownership."),
            ("loose (the|my|your|our|his|her|their|weight|track|interest|it)", ["lose $1"], "Use \"lose\"", "\"Lose\" means to misplace or fail to keep. \"Loose\" means not tight."),
            ("less (people|items|things|words|mistakes|errors|cars|books|students|employees|users|calories|options|steps|hours|days)", ["fewer $1"], "Use \"fewer\"", "Use \"fewer\" for things you can count and \"less\" for amounts."),
            ("between you and I", ["between you and me"], "Use \"me\"", "After a preposition like \"between\", use \"me\"."),
            ("for all intensive purposes", ["for all intents and purposes"], "Fix the idiom", "The phrase is \"for all intents and purposes\"."),
            ("could care less", ["couldn't care less"], "Fix the idiom", "\"Couldn't care less\" says you don't care at all."),
            ("supposably", ["supposedly"], "Use \"supposedly\"", "\"Supposedly\" means \"according to what is believed\"."),
            ("(an|the) affect (of|on)", ["$1 effect $2"], "Use \"effect\"", "\"Effect\" is usually the noun. \"Affect\" is usually the verb."),
            ("(would|will|can|could|might|may|must|should) effect", ["$1 affect"], "Use \"affect\"", "\"Affect\" is usually the verb meaning to influence."),
            ("(should|would|could|must) have went", ["$1 have gone"], "Use \"gone\"", "After \"have\", use the past participle \"gone\"."),
            ("(should|would|could|must) of went", ["$1 have gone"], "Use \"have gone\"", "After could/would/should, use \"have gone\"."),
            ("me and (him|her|them) (went|are|were|will|have|did|had|was)", ["$1 and I $2"], "Use \"and I\"", "When you're part of the subject, use \"I\" and put yourself last."),
            ("who's (car|house|idea|turn|phone|book|job)", ["whose $1"], "Use \"whose\"", "\"Whose\" shows ownership. \"Who's\" means \"who is\"."),
            ("try and", ["try to"], "Use \"try to\"", "\"Try to\" is the standard form in writing."),
            ("definately|definitly|defiantly(?= (agree|will|not|going|recommend))", ["definitely"], "Correct the spelling", "The word is spelled \"definitely\"."),
            ("recieve", ["receive"], "Correct the spelling", "Remember: i before e, except after c."),
            ("seperate", ["separate"], "Correct the spelling", "There's \"a rat\" in sep-a-rate."),
            ("occured", ["occurred"], "Correct the spelling", "\"Occurred\" has a double c and a double r."),
            ("untill", ["until"], "Correct the spelling", "\"Until\" has one l."),
            ("wich", ["which"], "Correct the spelling", "The word is \"which\"."),
            ("thier", ["their"], "Correct the spelling", "The word is \"their\"."),
        ]
    )
}

struct RepeatedWordRule: WritingRule {
    let id = "repeated-word"
    let category = IssueCategory.correctness
    static let re = NSRegularExpression.ci("\\b([A-Za-z']+)\\s+(\\1)\\b")
    static let allowed: Set<String> = ["had", "that", "is", "bye", "no", "very", "so", "ha", "knock", "tsk", "go", "yeah", "really"]

    func check(_ ctx: RuleContext) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            let first = ctx.sub(m.range(at: 1))
            guard !Self.allowed.contains(first.lowercased()) else { return nil }
            // Remove the second copy plus the whitespace before it.
            let firstEnd = m.range(at: 1).location + m.range(at: 1).length
            let r = NSRange(location: firstEnd, length: m.range.location + m.range.length - firstEnd)
            return Suggestion(
                ruleID: id, category: category, range: r, original: ctx.sub(r), replacements: [""],
                title: "Remove the repeated word",
                explanation: "\"\(first)\" appears twice in a row.",
                learnMore: "Repeated words are a common typo, especially across line breaks."
            )
        }
    }
}

struct ArticleRule: WritingRule {
    let id = "a-an"
    let category = IssueCategory.correctness
    static let re = NSRegularExpression.ci("\\b(a|an)\\s+([A-Za-z][A-Za-z'-]*)")
    static let silentH: Set<String> = ["hour", "hours", "hourly", "honest", "honestly", "honesty", "honor", "honors", "honour", "honorable", "heir", "heirs", "herb", "herbs"]
    static let consonantSoundPrefixes = ["uni", "use", "usu", "uti", "ura", "ure", "uro", "eu", "ewe", "one", "once", "ubiq", "uk", "ufo", "unanim"]

    static func startsWithVowelSound(_ word: String) -> Bool {
        let w = word.lowercased()
        if silentH.contains(w) || silentH.contains(where: { w.hasPrefix($0) && w.count <= $0.count + 3 }) { return true }
        if consonantSoundPrefixes.contains(where: { w.hasPrefix($0) }) { return false }
        guard let f = w.first else { return false }
        return "aeiou".contains(f)
    }

    func check(_ ctx: RuleContext) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            let articleRange = m.range(at: 1)
            let article = ctx.sub(articleRange)
            let next = ctx.sub(m.range(at: 2))
            // Acronyms and single letters depend on pronunciation, so skip them.
            if next.count == 1 || (next.count > 1 && next == next.uppercased()) { return nil }
            let wantsAn = Self.startsWithVowelSound(next)
            let isAn = article.lowercased() == "an"
            guard wantsAn != isAn else { return nil }
            let fix = TextUtils.matchCase(article, wantsAn ? "an" : "a")
            return Suggestion(
                ruleID: id, category: category, range: articleRange, original: article, replacements: [fix],
                title: wantsAn ? "Use \"an\"" : "Use \"a\"",
                explanation: wantsAn
                    ? "Use \"an\" before a word that starts with a vowel sound, like \"\(next)\"."
                    : "Use \"a\" before a word that starts with a consonant sound, like \"\(next)\".",
                learnMore: "The choice depends on sound, not spelling: \"an hour\", \"a university\"."
            )
        }
    }
}

struct LowercaseIRule: WritingRule {
    let id = "lowercase-i"
    let category = IssueCategory.correctness
    static let re = NSRegularExpression.cs("(?<![\\w.\\-/@'’])i(?=\\s|['’](?:m|ve|ll|d)\\b|[,;:!?]|$)")

    func check(_ ctx: RuleContext) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            guard !ctx.isInsideNonProse(m.range) else { return nil }
            return Suggestion(
                ruleID: id, category: category, range: m.range, original: "i", replacements: ["I"],
                title: "Capitalize \"I\"", explanation: "The pronoun \"I\" is always capitalized."
            )
        }
    }
}

struct SentenceCaseRule: WritingRule {
    let id = "sentence-case"
    let category = IssueCategory.correctness

    func check(_ ctx: RuleContext) -> [Suggestion] {
        var out: [Suggestion] = []
        for sentence in ctx.sentences {
            // Find the first letter of the sentence, skipping quotes, bullets and brackets.
            var i = sentence.range.location
            let end = sentence.range.location + sentence.range.length
            while i < end {
                let c = ctx.ns.character(at: i)
                if TextUtils.isLetter(c) || (c >= 48 && c <= 57) { break }
                i += 1
            }
            guard i < end else { continue }
            let c = ctx.ns.character(at: i)
            guard c >= 97 && c <= 122 else { continue }
            let wordRange = (ctx.text as NSString).rangeOfCharacter(
                from: CharacterSet.letters.inverted,
                options: [], range: NSRange(location: i, length: end - i))
            let wLen = wordRange.location == NSNotFound ? end - i : wordRange.location - i
            let r = NSRange(location: i, length: wLen)
            let word = ctx.sub(r)
            // Leave lowercase brand names and short chat fragments alone.
            if ["iphone", "ipad", "imac", "ios", "macos", "ebay", "etc", "e", "i"].contains(word.lowercased()) { continue }
            if ctx.isInsideNonProse(r) || sentence.wordCount < 3 { continue }
            out.append(Suggestion(
                ruleID: id, category: category, range: r, original: word,
                replacements: [word.prefix(1).uppercased() + word.dropFirst()],
                title: "Capitalize the first word",
                explanation: "Sentences start with a capital letter."
            ))
        }
        return out
    }
}

struct SpacingRule: WritingRule {
    let id = "spacing"
    let category = IssueCategory.correctness
    static let doubleSpace = NSRegularExpression.cs("(?<=[^\\s])  +(?=[^\\s])")
    static let spaceBeforePunct = NSRegularExpression.cs("(?<=[A-Za-z0-9)\"])[ \\t]+(?=[,.;:!?](?:\\s|$))")
    static let missingAfterComma = NSRegularExpression.cs("(?<=[a-z]),(?=[A-Za-z])")

    func check(_ ctx: RuleContext) -> [Suggestion] {
        var out: [Suggestion] = []
        for m in Self.doubleSpace.allMatches(ctx.text) where !ctx.isInsideNonProse(m.range) {
            out.append(Suggestion(ruleID: id, category: category, range: m.range, original: ctx.sub(m.range),
                                  replacements: [" "], title: "Remove the extra space",
                                  explanation: "Use a single space between words and sentences."))
        }
        for m in Self.spaceBeforePunct.allMatches(ctx.text) where !ctx.isInsideNonProse(m.range) {
            out.append(Suggestion(ruleID: id, category: category, range: m.range, original: ctx.sub(m.range),
                                  replacements: [""], title: "Remove the space before punctuation",
                                  explanation: "Punctuation sits right after the word, with no space before it."))
        }
        for m in Self.missingAfterComma.allMatches(ctx.text) where !ctx.isInsideNonProse(m.range) {
            out.append(Suggestion(ruleID: id, category: category, range: m.range, original: ",",
                                  replacements: [", "], title: "Add a space after the comma",
                                  explanation: "Put a space after a comma."))
        }
        return out
    }
}

struct OxfordCommaRule: WritingRule {
    let id = "oxford-comma"
    let category = IssueCategory.correctness
    // "apples, pears and plums" — a list of three or more without the final comma.
    static let re = NSRegularExpression.ci("\\b([A-Za-z]+(?: [A-Za-z]+)?), ([A-Za-z]+(?: [A-Za-z]+)?)( (?:and|or) )([A-Za-z]+)")

    func check(_ ctx: RuleContext) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            let secondItem = m.range(at: 2)
            let conj = m.range(at: 3)
            // Insert the comma by replacing the second item with "item,".
            let item = ctx.sub(secondItem)
            if item.split(separator: " ").count > 2 { return nil }
            _ = conj
            return Suggestion(
                ruleID: id, category: category, range: secondItem, original: item,
                replacements: [item + ","],
                title: "Add the Oxford comma",
                explanation: "In a list of three or more, a comma before the final \"and\" or \"or\" makes the list easier to read.",
                learnMore: "This is a style choice. You can turn off Oxford comma suggestions in Settings → Suggestions."
            )
        }
    }
}
