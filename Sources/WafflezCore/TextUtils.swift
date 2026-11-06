import Foundation

/// A sentence inside the text, in UTF-16 offsets.
public struct SentenceSpan: Hashable, Sendable {
    public var range: NSRange
    public var text: String
    public var wordCount: Int
}

/// A word inside the text, in UTF-16 offsets.
public struct WordSpan: Hashable, Sendable {
    public var range: NSRange
    public var text: String
    public var lower: String
}

public enum TextUtils {
    static let wordRegex = try! NSRegularExpression(pattern: "[A-Za-z\u{00C0}-\u{024F}]+(?:['’][A-Za-z]+)*", options: [])

    public static func words(in text: String) -> [WordSpan] {
        let ns = text as NSString
        return wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            let w = ns.substring(with: $0.range)
            return WordSpan(range: $0.range, text: w, lower: w.lowercased())
        }
    }

    public static func wordCount(_ text: String) -> Int {
        wordRegex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "eg", "ie",
        "inc", "ltd", "co", "corp", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept",
        "oct", "nov", "dec", "no", "fig", "approx", "dept", "est", "vol", "p", "pp", "u.s", "a.m", "p.m",
    ]

    /// Splits text into sentences without breaking on common abbreviations or decimals.
    public static func sentences(in text: String) -> [SentenceSpan] {
        let ns = text as NSString
        let length = ns.length
        var result: [SentenceSpan] = []
        var start = 0
        var i = 0

        func flush(_ endExclusive: Int) {
            var s = start
            var e = endExclusive
            while s < e, isSpace(ns.character(at: s)) { s += 1 }
            while e > s, isSpace(ns.character(at: e - 1)) { e -= 1 }
            if e > s {
                let r = NSRange(location: s, length: e - s)
                let t = ns.substring(with: r)
                result.append(SentenceSpan(range: r, text: t, wordCount: wordCount(t)))
            }
            start = endExclusive
        }

        while i < length {
            let c = ns.character(at: i)
            if c == 10 { // newline ends a sentence
                flush(i)
                start = i + 1
                i += 1
                continue
            }
            if c == 46 || c == 33 || c == 63 { // . ! ?
                var j = i + 1
                // Swallow runs like "?!" or "..." and closing quotes/brackets.
                while j < length {
                    let d = ns.character(at: j)
                    if d == 46 || d == 33 || d == 63 || d == 34 || d == 39 || d == 0x201D || d == 0x2019 || d == 41 { j += 1 } else { break }
                }
                let atEnd = j >= length
                let followedBySpace = !atEnd && isSpace(ns.character(at: j))
                if atEnd || followedBySpace {
                    if c == 46 && isAbbreviation(ns, dotAt: i) {
                        i = j
                        continue
                    }
                    flush(j)
                }
                i = j
                continue
            }
            i += 1
        }
        flush(length)
        return result
    }

    static func isAbbreviation(_ ns: NSString, dotAt index: Int) -> Bool {
        var s = index
        while s > 0 {
            let ch = ns.character(at: s - 1)
            if isLetter(ch) || ch == 46 { s -= 1 } else { break }
        }
        guard s < index else { return false }
        let token = ns.substring(with: NSRange(location: s, length: index - s)).lowercased()
        if abbreviations.contains(token) { return true }
        // Single capital letter initials like "J. Smith".
        if token.count == 1, let f = token.unicodeScalars.first, CharacterSet.letters.contains(f) {
            return true
        }
        return false
    }

    static func isSpace(_ c: unichar) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0
    }

    static func isLetter(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 0xC0 && c <= 0x24F)
    }

    /// Makes `replacement` follow the capitalization of `original`.
    public static func matchCase(_ original: String, _ replacement: String) -> String {
        guard let first = original.first, !replacement.isEmpty else { return replacement }
        let letters = original.filter { $0.isLetter }
        if letters.count > 1, letters == letters.uppercased(), letters != letters.lowercased() {
            return replacement.uppercased()
        }
        if first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    /// Rough English syllable count for readability scores.
    public static func syllables(_ word: String) -> Int {
        let w = word.lowercased().filter { $0.isLetter }
        if w.isEmpty { return 0 }
        if w.count <= 3 { return 1 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevVowel = false
        for ch in w {
            let v = vowels.contains(ch)
            if v && !prevVowel { count += 1 }
            prevVowel = v
        }
        if w.hasSuffix("e") && !w.hasSuffix("le") && count > 1 { count -= 1 }
        if w.hasSuffix("ed") && !w.hasSuffix("ted") && !w.hasSuffix("ded") && count > 1 { count -= 1 }
        return max(1, count)
    }

    /// Escapes text for use inside a regex pattern.
    public static func escapeRegex(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    /// Safe substring by UTF-16 range.
    public static func substring(_ text: String, _ range: NSRange) -> String {
        let ns = text as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return "" }
        return ns.substring(with: range)
    }

    /// Applies a replacement and returns the new text.
    public static func replacing(_ text: String, range: NSRange, with replacement: String) -> String {
        let ns = text as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return text }
        return ns.replacingCharacters(in: range, with: replacement)
    }

    /// Applies many non-overlapping replacements at once (last to first so offsets stay valid).
    public static func applying(_ edits: [(NSRange, String)], to text: String) -> String {
        var result = text as NSString
        var lastStart = Int.max
        for (range, rep) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard range.location + range.length <= lastStart else { continue } // skip overlaps
            guard range.location + range.length <= result.length else { continue }
            result = result.replacingCharacters(in: range, with: rep) as NSString
            lastStart = range.location
        }
        return result as String
    }

    public static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "so", "of", "to", "in", "on", "at", "by",
        "for", "with", "about", "as", "into", "like", "through", "after", "over", "between", "out",
        "against", "during", "without", "before", "under", "around", "among", "is", "are", "was",
        "were", "be", "been", "being", "am", "do", "does", "did", "have", "has", "had", "i", "you",
        "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his",
        "its", "our", "their", "this", "that", "these", "those", "there", "here", "what", "which",
        "who", "whom", "whose", "when", "where", "why", "how", "not", "no", "yes", "all", "any",
        "each", "few", "more", "most", "other", "some", "such", "only", "own", "same", "than",
        "too", "very", "can", "will", "just", "should", "would", "could", "may", "might", "must",
        "also", "from", "up", "down", "off", "again", "further", "once", "because", "while",
        "until", "both", "nor", "now", "even", "ever", "still", "yet", "every", "much", "many",
        "well", "back", "way", "one", "two", "it's", "i'm", "don't", "can't", "we're", "they're",
        "you're", "that's", "let", "make", "get", "got", "say", "said", "know", "think", "people",
        "time", "really", "thing", "things", "something", "anything", "everything", "nothing",
        "being", "which", "within", "upon", "however", "therefore", "though", "although",
    ]
}

extension NSRegularExpression {
    /// Convenience: case-insensitive regex that must compile (patterns are static).
    static func ci(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static func cs(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    func allMatches(_ text: String) -> [NSTextCheckingResult] {
        matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length))
    }
}
