import Foundation

public struct AIDetectionSentence: Hashable, Codable, Sendable, Identifiable {
    public var id: Int { location }
    public var location: Int
    public var length: Int
    public var text: String
    public var score: Double
    public var reasons: [String]
    public var range: NSRange { NSRange(location: location, length: length) }
}

public struct AIDetectionReport: Hashable, Codable, Sendable {
    /// Estimated share of the text that reads as AI-written, 0–100.
    public var percent: Int
    public var sentences: [AIDetectionSentence]
    public var signals: [String]
    public var wordCount: Int
    public var enoughText: Bool

    public var flagged: [AIDetectionSentence] { sentences.filter { $0.score >= AIDetector.flagThreshold } }

    public var verdict: String {
        guard enoughText else { return "Add at least \(AIDetector.minimumWords) words for an estimate." }
        switch percent {
        case ..<15: return "Reads as human-written"
        case 15..<40: return "Mostly reads as human-written"
        case 40..<70: return "Mix of human and AI-like writing"
        default: return "Reads as mostly AI-written"
        }
    }
}

/// On-device estimate of how much text reads as AI-written.
/// It looks at writing patterns (sentence rhythm, stock AI phrases, contractions, uniform paragraphs).
/// This is an estimate, not proof — no detector can prove who wrote something.
public struct AIDetector: Sendable {
    public static let minimumWords = 40
    public static let flagThreshold = 0.55

    public init() {}

    /// Phrases that show up far more often in AI-generated prose than in human writing.
    public static let tellPhrases: [String] = [
        "delve", "delves", "delving", "tapestry", "testament to", "in today's fast-paced", "in today's digital",
        "it's important to note", "it is important to note", "it's worth noting", "it is worth noting",
        "navigate the complexities", "navigating the complexities", "ever-evolving", "ever-changing landscape",
        "landscape of", "realm of", "in the realm", "multifaceted", "pivotal", "seamless", "seamlessly",
        "robust", "foster", "fostering", "leverage", "leveraging", "harness the power", "unlock the potential",
        "unleash", "elevate your", "embark on", "a journey of", "game-changer", "game changer", "cutting-edge",
        "plethora", "myriad of", "a myriad", "furthermore", "moreover", "additionally", "in conclusion",
        "in summary", "ultimately,", "overall,", "underscores", "underscore the", "showcasing", "showcases",
        "meticulous", "meticulously", "intricate", "intricacies", "paramount", "vibrant", "bustling", "nestled",
        "a rich history", "rich tapestry", "stands as a", "serves as a", "plays a crucial role", "plays a vital role",
        "crucial role", "vital role", "key role", "not only", "but also", "whether you're", "look no further",
        "dive into", "dive deeper", "deep dive", "let's explore", "in essence", "holistic", "synergy",
        "commendable", "invaluable", "insightful", "resonate", "resonates", "embrace", "empower", "empowering",
        "transformative", "groundbreaking", "streamline", "optimize your", "comprehensive guide", "navigate",
        "bolster", "realm", "beacon", "symphony", "labyrinth", "enigma", "interplay", "nuanced", "nuances",
    ]

    static let transitions: Set<String> = [
        "additionally", "furthermore", "moreover", "however", "overall", "ultimately", "consequently",
        "therefore", "in conclusion", "in summary", "notably", "importantly", "similarly", "thus", "hence",
    ]

    public func analyze(_ text: String) -> AIDetectionReport {
        let words = TextUtils.wordCount(text)
        let sentences = TextUtils.sentences(in: text).filter { $0.wordCount >= 3 }
        guard words >= Self.minimumWords, sentences.count >= 3 else {
            return AIDetectionReport(percent: 0, sentences: [], signals: [], wordCount: words, enoughText: false)
        }

        // 1. Burstiness: humans vary sentence length a lot; AI tends to be even.
        let lengths = sentences.map { Double($0.wordCount) }
        let mean = lengths.reduce(0, +) / Double(lengths.count)
        let variance = lengths.reduce(0) { $0 + pow($1 - mean, 2) } / Double(lengths.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 0
        let burstScore = clamp((0.6 - cv) / 0.35)

        // 2. Stock phrases.
        let lower = text.lowercased()
        var tellHits = 0
        var tellsFound: [String: Int] = [:]
        for phrase in Self.tellPhrases {
            let n = countWholeWord(phrase, in: lower)
            if n > 0 { tellHits += n; tellsFound[phrase] = n }
        }
        let tellDensity = Double(tellHits) / Double(words) * 100
        let tellScore = clamp(tellDensity / 2.2)

        // 3. Contractions: people use them; AI often avoids them.
        let contractions = NSRegularExpression.ci("\\b\\w+['’](t|s|re|ve|ll|d|m)\\b").allMatches(text).count
        let contractionRate = Double(contractions) / Double(words) * 100
        let contractionScore = clamp(1 - contractionRate / 2.0)

        // 4. Em dashes and "rule of three" lists.
        let emDashes = text.components(separatedBy: "—").count - 1
        let emScore = clamp(Double(emDashes) / Double(words) * 100 / 1.2)
        let triads = NSRegularExpression.ci("\\b\\w+, \\w+,? and \\w+\\b").allMatches(text).count
        let triadScore = clamp(Double(triads) / Double(sentences.count) * 2.5)

        // 5. Uniform paragraphs.
        let paragraphs = text.components(separatedBy: "\n").map { TextUtils.wordCount($0) }.filter { $0 > 0 }
        var paragraphScore = 0.0
        if paragraphs.count >= 3 {
            let pm = Double(paragraphs.reduce(0, +)) / Double(paragraphs.count)
            let pv = paragraphs.reduce(0.0) { $0 + pow(Double($1) - pm, 2) } / Double(paragraphs.count)
            let pcv = pm > 0 ? sqrt(pv) / pm : 1
            paragraphScore = clamp((0.45 - pcv) / 0.35)
        }

        // 6. Sentences starting with transition words.
        let transitionStarts = sentences.filter { s in
            let first = s.text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).first.map(String.init) ?? ""
            return Self.transitions.contains(first)
        }.count
        let transitionScore = clamp(Double(transitionStarts) / Double(sentences.count) * 3)

        let global = 0.26 * burstScore + 0.30 * tellScore + 0.12 * contractionScore + 0.08 * emScore
            + 0.08 * triadScore + 0.06 * paragraphScore + 0.10 * transitionScore

        // Per-sentence scores so we can highlight the AI-like parts.
        var scored: [AIDetectionSentence] = []
        for s in sentences {
            var reasons: [String] = []
            let sl = s.text.lowercased()
            var local = 0.0
            let tells = Self.tellPhrases.filter { countWholeWord($0, in: sl) > 0 }
            if !tells.isEmpty {
                local += min(0.5, Double(tells.count) * 0.22)
                reasons.append("Uses stock AI phrasing: " + tells.prefix(3).map { "\"\($0)\"" }.joined(separator: ", "))
            }
            let first = sl.split(whereSeparator: { $0 == " " || $0 == "," }).first.map(String.init) ?? ""
            if Self.transitions.contains(first) { local += 0.15; reasons.append("Opens with a stock transition") }
            if abs(Double(s.wordCount) - mean) < max(3, mean * 0.2) && cv < 0.45 { local += 0.12; reasons.append("Same length as the sentences around it") }
            if s.text.contains("—") { local += 0.08; reasons.append("Uses an em dash") }
            if NSRegularExpression.ci("\\b\\w+, \\w+,? and \\w+\\b").allMatches(s.text).count > 0 { local += 0.08; reasons.append("Uses a list of three") }
            if NSRegularExpression.ci("\\b\\w+['’](t|s|re|ve|ll|d|m)\\b").allMatches(s.text).isEmpty && s.wordCount > 12 { local += 0.05 }
            let score = clamp(local * 0.75 + global * 0.6)
            scored.append(AIDetectionSentence(location: s.range.location, length: s.range.length, text: s.text, score: score, reasons: reasons))
        }

        let flaggedWords = scored.filter { $0.score >= Self.flagThreshold }.reduce(0) { $0 + TextUtils.wordCount($1.text) }
        let share = Double(flaggedWords) / Double(words)
        let percent = Int((clamp(share * 0.7 + global * 0.45) * 100).rounded())

        var signals: [String] = []
        signals.append(cv < 0.4
            ? "Sentence lengths are very even (variation \(String(format: "%.2f", cv))). Human writing usually varies more."
            : "Sentence lengths vary naturally (variation \(String(format: "%.2f", cv))).")
        if !tellsFound.isEmpty {
            let top = tellsFound.sorted { $0.value > $1.value }.prefix(5).map { "\"\($0.key)\"" }.joined(separator: ", ")
            signals.append("Found \(tellHits) stock AI phrase\(tellHits == 1 ? "" : "s"), such as \(top).")
        }
        signals.append(contractionRate < 0.5 ? "Almost no contractions, which is common in AI text." : "Uses contractions like natural speech.")
        if emDashes > 1 { signals.append("Uses \(emDashes) em dashes.") }
        if transitionStarts > 1 { signals.append("\(transitionStarts) sentences start with stock transitions like \"Additionally\" or \"Moreover\".") }

        return AIDetectionReport(percent: percent, sentences: scored, signals: signals, wordCount: words, enoughText: true)
    }

    static let compiledTells: [String: NSRegularExpression] = Dictionary(uniqueKeysWithValues: Set(tellPhrases).map { phrase in
        (phrase, try! NSRegularExpression(pattern: "(?<![a-z])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![a-z])"))
    })

    private func countWholeWord(_ phrase: String, in lower: String) -> Int {
        guard let re = Self.compiledTells[phrase] else { return 0 }
        return re.numberOfMatches(in: lower, range: NSRange(location: 0, length: (lower as NSString).length))
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
