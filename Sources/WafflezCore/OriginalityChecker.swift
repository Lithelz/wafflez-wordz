import Foundation

/// A document to compare against (your library, a sources folder, or pasted text).
public struct SourceDocument: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var title: String
    public var text: String
    public var url: String?
    public init(title: String, text: String, url: String? = nil) {
        self.title = title
        self.text = text
        self.url = url
    }
}

public struct OriginalityMatch: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var sourceTitle: String
    public var sourceURL: String?
    /// Share of your text that matches this source, 0–100.
    public var percent: Int
    /// Matching passages in your text (UTF-16 ranges).
    public var passages: [NSRangeCodable]
    public var excerpt: String
}

public struct NSRangeCodable: Hashable, Codable, Sendable {
    public var location: Int
    public var length: Int
    public var range: NSRange { NSRange(location: location, length: length) }
    public init(_ r: NSRange) { location = r.location; length = r.length }
}

public struct OriginalityReport: Hashable, Codable, Sendable {
    public var matches: [OriginalityMatch]
    /// Share of your text that matches any source, 0–100.
    public var matchedPercent: Int
    public var originalPercent: Int { 100 - matchedPercent }
}

/// Finds passages that overlap with other documents using 6-word shingles.
public struct OriginalityChecker: Sendable {
    public var shingleSize = 6
    public init() {}

    struct Token { let word: String; let range: NSRange }

    func tokens(_ text: String) -> [Token] {
        TextUtils.words(in: text).map { Token(word: $0.lower.replacingOccurrences(of: "’", with: "'"), range: $0.range) }
    }

    public func check(_ text: String, against sources: [SourceDocument], ignoreQuotes: Bool = true) -> OriginalityReport {
        let mine = tokens(text)
        guard mine.count >= shingleSize else { return OriginalityReport(matches: [], matchedPercent: 0) }
        let quoted = ignoreQuotes ? quotedRanges(text) : []
        var everMatched = Set<Int>()
        var matches: [OriginalityMatch] = []

        for source in sources {
            let theirs = tokens(source.text)
            guard theirs.count >= shingleSize else { continue }
            var set = Set<String>()
            for i in 0...(theirs.count - shingleSize) {
                set.insert(theirs[i..<(i + shingleSize)].map(\.word).joined(separator: " "))
            }
            var matchedTokens = Set<Int>()
            for i in 0...(mine.count - shingleSize) {
                let key = mine[i..<(i + shingleSize)].map(\.word).joined(separator: " ")
                if set.contains(key) {
                    for j in i..<(i + shingleSize) { matchedTokens.insert(j) }
                }
            }
            // Ignore text inside quotation marks (it's already credited).
            matchedTokens = matchedTokens.filter { idx in !quoted.contains { NSIntersectionRange($0, mine[idx].range).length > 0 } }
            guard !matchedTokens.isEmpty else { continue }
            everMatched.formUnion(matchedTokens)
            let passages = merge(matchedTokens.sorted(), mine)
            let excerpt = passages.first.map { (text as NSString).substring(with: $0) } ?? ""
            matches.append(OriginalityMatch(
                sourceTitle: source.title, sourceURL: source.url,
                percent: Int((Double(matchedTokens.count) / Double(mine.count) * 100).rounded()),
                passages: passages.map(NSRangeCodable.init), excerpt: String(excerpt.prefix(280))
            ))
        }
        matches.sort { $0.percent > $1.percent }
        let total = Int((Double(everMatched.count) / Double(mine.count) * 100).rounded())
        return OriginalityReport(matches: matches, matchedPercent: total)
    }

    private func merge(_ indexes: [Int], _ toks: [Token]) -> [NSRange] {
        var out: [NSRange] = []
        var start: Int?
        var prev = -2
        for i in indexes {
            if i != prev + 1, let s = start {
                out.append(span(toks[s].range, toks[prev].range))
                start = i
            } else if start == nil {
                start = i
            }
            prev = i
        }
        if let s = start { out.append(span(toks[s].range, toks[prev].range)) }
        return out
    }

    private func span(_ a: NSRange, _ b: NSRange) -> NSRange {
        NSRange(location: a.location, length: b.location + b.length - a.location)
    }

    private func quotedRanges(_ text: String) -> [NSRange] {
        NSRegularExpression.cs("[\"“][^\"”]{3,}[\"”]").allMatches(text).map(\.range)
    }
}
