import Foundation

/// One change the humanizer suggests. Offsets are UTF-16 in the original text.
public struct HumanizeChange: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID = UUID()
    public var location: Int
    public var length: Int
    public var original: String
    public var replacement: String
    public var reason: String
    public var range: NSRange { NSRange(location: location, length: length) }
}

/// Voices the AI humanizer can write in.
public enum HumanizeVoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case natural, casual, professional, academic, storyteller, myVoice
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .natural: return "Natural"
        case .casual: return "Casual"
        case .professional: return "Professional"
        case .academic: return "Academic"
        case .storyteller: return "Storyteller"
        case .myVoice: return "My voice"
        }
    }
    public var guidance: String {
        switch self {
        case .natural: return "Plain, conversational and clear, like a thoughtful person writing quickly but carefully."
        case .casual: return "Relaxed and friendly, with contractions and short sentences, like a message to a friend."
        case .professional: return "Polished and direct, like a capable colleague. Contractions are fine. No buzzwords."
        case .academic: return "Precise and measured, suitable for a university paper, but without stiff filler or stock phrases."
        case .storyteller: return "Vivid and personal, with concrete detail and varied rhythm."
        case .myVoice: return "Match the writer's own voice from the sample provided."
        }
    }
}

/// Offline humanizer: swaps stock AI phrases for plain words, adds contractions, and loosens rhythm.
/// The AI humanizer (in AIClient prompts) does a deeper rewrite; this one works without a key.
public struct LocalHumanizer: Sendable {
    public init() {}

    static let swaps: [(String, String, String)] = [
        ("in today's fast-paced world,? ", "", "Stock opener"),
        ("in today's digital age,? ", "", "Stock opener"),
        ("it's important to note that ", "", "Filler phrase"),
        ("it is important to note that ", "", "Filler phrase"),
        ("it's worth noting that ", "", "Filler phrase"),
        ("it is worth noting that ", "", "Filler phrase"),
        ("delve into", "dig into", "Stock AI word"),
        ("delves into", "digs into", "Stock AI word"),
        ("delving into", "digging into", "Stock AI word"),
        ("a testament to", "proof of", "Stock AI phrase"),
        ("navigate the complexities of", "handle", "Stock AI phrase"),
        ("navigating the complexities of", "handling", "Stock AI phrase"),
        ("embark on a journey", "start", "Stock AI phrase"),
        ("embark on", "start", "Stock AI phrase"),
        ("rich tapestry", "mix", "Stock AI phrase"),
        ("tapestry", "mix", "Stock AI word"),
        ("plethora of", "lots of", "Stock AI word"),
        ("a myriad of", "many", "Stock AI word"),
        ("myriad", "many", "Stock AI word"),
        ("plays a crucial role in", "matters for", "Stock AI phrase"),
        ("plays a vital role in", "matters for", "Stock AI phrase"),
        ("plays a pivotal role in", "matters for", "Stock AI phrase"),
        ("unlock the potential of", "get more out of", "Stock AI phrase"),
        ("harness the power of", "use", "Stock AI phrase"),
        ("ever-evolving", "changing", "Stock AI word"),
        ("cutting-edge", "new", "Stock AI word"),
        ("game-changer", "big deal", "Stock AI word"),
        ("seamlessly", "smoothly", "Stock AI word"),
        ("seamless", "smooth", "Stock AI word"),
        ("leverage", "use", "Stock AI word"),
        ("leveraging", "using", "Stock AI word"),
        ("utilize", "use", "Stock AI word"),
        ("utilizing", "using", "Stock AI word"),
        ("robust", "strong", "Stock AI word"),
        ("pivotal", "key", "Stock AI word"),
        ("foster", "build", "Stock AI word"),
        ("fostering", "building", "Stock AI word"),
        ("realm", "world", "Stock AI word"),
        ("elevate", "improve", "Stock AI word"),
        ("streamline", "simplify", "Stock AI word"),
        ("empower", "help", "Stock AI word"),
        ("underscores", "shows", "Stock AI word"),
        ("showcases", "shows", "Stock AI word"),
        ("showcasing", "showing", "Stock AI word"),
        ("multifaceted", "complex", "Stock AI word"),
        ("intricate", "detailed", "Stock AI word"),
        ("paramount", "most important", "Stock AI word"),
        ("meticulous", "careful", "Stock AI word"),
        ("meticulously", "carefully", "Stock AI word"),
        ("bustling", "busy", "Stock AI word"),
        ("vibrant", "lively", "Stock AI word"),
        ("nestled", "tucked", "Stock AI word"),
        ("comprehensive", "thorough", "Stock AI word"),
        ("commence", "start", "Stock AI word"),
        ("endeavor", "effort", "Stock AI word"),
        ("furthermore,", "also,", "Stiff transition"),
        ("moreover,", "plus,", "Stiff transition"),
        ("additionally,", "also,", "Stiff transition"),
        ("in conclusion,", "so,", "Stiff transition"),
        ("in summary,", "in short,", "Stiff transition"),
        ("ultimately,", "in the end,", "Stiff transition"),
        ("do not", "don't", "Add a contraction"),
        ("does not", "doesn't", "Add a contraction"),
        ("did not", "didn't", "Add a contraction"),
        ("is not", "isn't", "Add a contraction"),
        ("are not", "aren't", "Add a contraction"),
        ("was not", "wasn't", "Add a contraction"),
        ("cannot", "can't", "Add a contraction"),
        ("will not", "won't", "Add a contraction"),
        ("would not", "wouldn't", "Add a contraction"),
        ("should not", "shouldn't", "Add a contraction"),
        ("could not", "couldn't", "Add a contraction"),
        ("it is", "it's", "Add a contraction"),
        ("that is", "that's", "Add a contraction"),
        ("there is", "there's", "Add a contraction"),
        ("i am", "I'm", "Add a contraction"),
        ("we are", "we're", "Add a contraction"),
        ("they are", "they're", "Add a contraction"),
        ("you are", "you're", "Add a contraction"),
        ("let us", "let's", "Add a contraction"),
    ]

    static let compiled: [(NSRegularExpression, String, String)] = swaps.map {
        // Only require a word boundary at the end when the phrase ends in a letter.
        (NSRegularExpression.ci("(?<![A-Za-z'’])" + $0.0 + ($0.0.last?.isLetter == true ? "(?![A-Za-z])" : "")), $0.1, $0.2)
    }

    public func suggestions(for text: String) -> [HumanizeChange] {
        let ns = text as NSString
        var changes: [HumanizeChange] = []
        for (re, rep, reason) in Self.compiled {
            for m in re.allMatches(text) {
                let original = ns.substring(with: m.range)
                var replacement = TextUtils.matchCase(original, rep)
                // A deleted opener leaves the next word lowercase; capitalize it.
                var range = m.range
                if rep.isEmpty {
                    let after = range.location + range.length
                    if after < ns.length {
                        let next = ns.substring(with: NSRange(location: after, length: 1))
                        if original.first?.isUppercase == true {
                            range.length += 1
                            replacement = next.uppercased()
                        }
                    }
                }
                changes.append(HumanizeChange(location: range.location, length: range.length, original: ns.substring(with: range), replacement: replacement, reason: reason))
            }
        }
        // Em dashes are a common AI tell; swap every other one for a comma.
        let dash = NSRegularExpression.cs("\\s?—\\s?")
        for (i, m) in dash.allMatches(text).enumerated() where i % 2 == 0 {
            changes.append(HumanizeChange(location: m.range.location, length: m.range.length, original: ns.substring(with: m.range), replacement: ", ", reason: "Em dash"))
        }
        // Drop overlaps, keeping the earliest.
        var kept: [HumanizeChange] = []
        for c in changes.sorted(by: { $0.location < $1.location }) {
            if let last = kept.last, c.location < last.location + last.length { continue }
            kept.append(c)
        }
        return kept
    }

    public func humanize(_ text: String) -> String {
        TextUtils.applying(suggestions(for: text).map { ($0.range, $0.replacement) }, to: text)
    }
}
