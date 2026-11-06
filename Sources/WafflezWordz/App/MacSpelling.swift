import AppKit
import CoreServices
import WafflezCore

/// Spelling and grammar from the built-in macOS checker, on device.
struct MacSpellingProvider: SpellingProvider {
    private func orthography(_ language: String) -> [NSSpellChecker.OptionKey: Any] {
        [.orthography: NSOrthography(dominantScript: "Latn", languageMap: ["Latn": [language, "en"]])]
    }

    func misspellings(in text: String, language: String) -> [(range: NSRange, guesses: [String])] {
        let checker = NSSpellChecker.shared
        let length = (text as NSString).length
        guard length > 0 else { return [] }
        let results = checker.check(text, range: NSRange(location: 0, length: length),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                    options: orthography(language), inSpellDocumentWithTag: 0,
                                    orthography: nil, wordCount: nil)
        return results.prefix(300).map { r in
            let guesses = checker.guesses(forWordRange: r.range, in: text, language: language, inSpellDocumentWithTag: 0) ?? []
            return (r.range, guesses)
        }
    }

    func grammarIssues(in text: String, language: String) -> [(range: NSRange, message: String, fixes: [String])] {
        let checker = NSSpellChecker.shared
        let length = (text as NSString).length
        guard length > 0 else { return [] }
        let results = checker.check(text, range: NSRange(location: 0, length: length),
                                    types: NSTextCheckingResult.CheckingType.grammar.rawValue,
                                    options: orthography(language), inSpellDocumentWithTag: 0,
                                    orthography: nil, wordCount: nil)
        var out: [(NSRange, String, [String])] = []
        for r in results.prefix(100) {
            for detail in r.grammarDetails ?? [] {
                // Detail ranges are relative to the sentence the checker returned.
                guard let value = detail["NSGrammarRange"] as? NSValue else { continue }
                let rel = value.rangeValue
                let abs = NSRange(location: r.range.location + rel.location, length: rel.length)
                guard abs.location + abs.length <= length, abs.length > 0 else { continue }
                let message = detail["NSGrammarUserDescription"] as? String ?? "Possible grammar issue."
                let fixes = detail["NSGrammarCorrections"] as? [String] ?? []
                out.append((abs, message, fixes))
            }
        }
        return out
    }
}

/// Word definitions from the macOS Dictionary app (offline).
enum Definitions {
    static func define(_ word: String) -> String? {
        let w = word.trimmed
        guard !w.isEmpty else { return nil }
        let range = CFRange(location: 0, length: (w as NSString).length)
        guard let def = DCSCopyTextDefinition(nil, w as CFString, range)?.takeRetainedValue() else { return nil }
        let text = def as String
        // Keep it readable in a small card.
        return text.count > 600 ? String(text.prefix(600)) + "…" : text
    }

    /// Quick synonyms from the built-in thesaurus list, before asking AI.
    static func localSynonyms(_ word: String) -> [String] {
        let lower = word.lowercased()
        return Thesaurus.synonyms(lower)
    }
}
