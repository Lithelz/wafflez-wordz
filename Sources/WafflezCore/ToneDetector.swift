import Foundation

public struct ToneScore: Hashable, Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var emoji: String
    public var strength: Double // 0...1
}

public struct ToneResult: Hashable, Codable, Sendable {
    public var tones: [ToneScore]          // strongest first
    public var formality: Double           // 0 casual ... 1 formal
    public var confidence: Double          // 0 unsure ... 1 confident
    public var friendliness: Double        // 0 cool ... 1 warm
    public var primary: ToneScore? { tones.first }
    public var summary: String {
        guard let p = primary else { return "Neutral" }
        if tones.count > 1 { return "\(p.name), \(tones[1].name.lowercased())" }
        return p.name
    }
}

/// Predicts how a reader will likely hear the message. Runs entirely on device.
public struct ToneDetector: Sendable {
    public static let minimumCharacters = 150
    public static let maximumCharacters = 20_000

    public init() {}

    struct Lexicon {
        let name: String
        let emoji: String
        let words: [String]
    }

    static let lexicons: [Lexicon] = [
        Lexicon(name: "Confident", emoji: "😎", words: ["will", "definitely", "certainly", "confident", "ensure", "guarantee", "clearly", "absolutely", "without a doubt", "i'm sure", "we will", "i will", "committed", "proven"]),
        Lexicon(name: "Friendly", emoji: "😊", words: ["hope", "glad", "happy", "great to", "love", "thanks", "thank you", "cheers", "hi ", "hello", ":)", "🙂", "😊", "welcome", "nice to", "pleasure", "enjoy"]),
        Lexicon(name: "Appreciative", emoji: "🙏", words: ["thank you", "thanks", "appreciate", "grateful", "thankful", "kind of you", "means a lot", "recognize your"]),
        Lexicon(name: "Optimistic", emoji: "🌤️", words: ["looking forward", "excited", "opportunity", "promising", "bright", "can't wait", "progress", "improve", "growth", "potential", "optimistic"]),
        Lexicon(name: "Excited", emoji: "🤩", words: ["excited", "thrilled", "can't wait", "amazing", "awesome", "incredible", "wow", "fantastic", "!!"]),
        Lexicon(name: "Worried", emoji: "😟", words: ["worried", "concern", "concerned", "afraid", "anxious", "nervous", "risk", "unsure", "uncertain", "fear", "uneasy", "trouble"]),
        Lexicon(name: "Apologetic", emoji: "😔", words: ["sorry", "apologize", "apologies", "my fault", "my mistake", "regret", "forgive", "my bad"]),
        Lexicon(name: "Frustrated", emoji: "😤", words: ["frustrated", "annoyed", "again", "still haven't", "still not", "ridiculous", "unacceptable", "disappointed", "as per my last", "how many times"]),
        Lexicon(name: "Urgent", emoji: "⏰", words: ["urgent", "asap", "immediately", "deadline", "right away", "as soon as possible", "by end of day", "eod", "time-sensitive", "today"]),
        Lexicon(name: "Curious", emoji: "🤔", words: ["wonder", "curious", "how does", "why does", "what if", "could you explain", "i'd love to know"]),
        Lexicon(name: "Tentative", emoji: "🫣", words: ["maybe", "perhaps", "might", "possibly", "i think", "i guess", "kind of", "sort of", "just wanted", "not sure", "if that's okay", "i feel like"]),
        Lexicon(name: "Formal", emoji: "🎩", words: ["therefore", "furthermore", "regarding", "sincerely", "hereby", "pursuant", "kindly", "accordingly", "dear", "respectfully", "in addition"]),
        Lexicon(name: "Informal", emoji: "👋", words: ["hey", "lol", "gonna", "wanna", "yeah", "cool", "btw", "omg", "haha", "kinda", "stuff", "guys"]),
        Lexicon(name: "Direct", emoji: "🎯", words: ["please send", "send me", "i need", "you need to", "do this", "make sure", "must", "required", "let's"]),
        Lexicon(name: "Encouraging", emoji: "💪", words: ["you can", "you've got this", "keep it up", "proud", "well done", "great job", "nice work", "believe in"]),
        Lexicon(name: "Disappointed", emoji: "😞", words: ["disappointed", "unfortunately", "expected more", "let down", "not what", "fell short", "sadly"]),
    ]

    public func detect(_ text: String) -> ToneResult? {
        guard text.count >= Self.minimumCharacters else { return nil }
        let clipped = text.count > Self.maximumCharacters ? String(text.prefix(Self.maximumCharacters)) : text
        let lower = " " + clipped.lowercased() + " "
        let words = max(1, TextUtils.wordCount(clipped))
        let per100 = 100.0 / Double(words)

        var scores: [(Lexicon, Double)] = []
        for lex in Self.lexicons {
            var hits = 0.0
            for w in lex.words {
                hits += Double(lower.components(separatedBy: w).count - 1)
            }
            scores.append((lex, hits * per100))
        }

        // Punctuation signals.
        let exclaims = Double(clipped.filter { $0 == "!" }.count) * per100
        let questions = Double(clipped.filter { $0 == "?" }.count) * per100
        bump(&scores, "Excited", exclaims * 0.6)
        bump(&scores, "Friendly", exclaims * 0.3)
        bump(&scores, "Curious", questions * 0.8)

        // Contractions push toward informal; long words toward formal.
        let contractions = Double(NSRegularExpression.ci("\\b\\w+['’](t|s|re|ve|ll|d|m)\\b").allMatches(clipped).count) * per100
        let longWords = Double(TextUtils.words(in: clipped).filter { $0.text.count >= 9 }.count) * per100
        bump(&scores, "Informal", contractions * 0.25)
        bump(&scores, "Formal", max(0, longWords - 6) * 0.3)

        let ranked = scores
            .filter { $0.1 >= 0.9 }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { ToneScore(name: $0.0.name, emoji: $0.0.emoji, strength: min(1, $0.1 / 6)) }

        let tones = ranked.isEmpty ? [ToneScore(name: "Neutral", emoji: "😐", strength: 0.5)] : Array(ranked)

        func value(_ name: String) -> Double { scores.first { $0.0.name == name }?.1 ?? 0 }
        let formality = clamp(0.5 + (value("Formal") - value("Informal")) / 8)
        let confidence = clamp(0.6 + (value("Confident") + value("Direct") - value("Tentative") * 1.5 - value("Apologetic")) / 8)
        let friendliness = clamp(0.5 + (value("Friendly") + value("Appreciative") + value("Encouraging") - value("Frustrated") * 1.5) / 8)
        return ToneResult(tones: tones, formality: formality, confidence: confidence, friendliness: friendliness)
    }

    private func bump(_ scores: inout [(Lexicon, Double)], _ name: String, _ amount: Double) {
        if let i = scores.firstIndex(where: { $0.0.name == name }) { scores[i].1 += amount }
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
