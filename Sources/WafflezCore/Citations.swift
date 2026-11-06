import Foundation

public enum CitationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case apa = "APA", mla = "MLA", chicago = "Chicago"
    public var id: String { rawValue }
    public var fullName: String {
        switch self {
        case .apa: return "APA 7th edition"
        case .mla: return "MLA 9th edition"
        case .chicago: return "Chicago 17th (author-date)"
        }
    }
}

public enum SourceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case website, book, journal, news
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

/// Details of one source. Fill what you know; the formatter skips blanks.
public struct CitationSource: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var kind: SourceKind = .website
    public var authors: [String] = []      // "First Last"
    public var title: String = ""
    public var container: String = ""      // website, journal or newspaper name
    public var publisher: String = ""
    public var year: String = ""
    public var month: String = ""
    public var day: String = ""
    public var volume: String = ""
    public var issue: String = ""
    public var pages: String = ""
    public var url: String = ""
    public var accessed: Date? = nil
    public init() {}
}

public enum CitationFormatter {
    struct Name { let first: String; let last: String }

    static func split(_ full: String) -> Name {
        let trimmed = full.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return Name(first: parts.count > 1 ? parts[1] : "", last: parts[0])
        }
        var parts = trimmed.split(separator: " ").map(String.init)
        guard let last = parts.popLast() else { return Name(first: "", last: "") }
        return Name(first: parts.joined(separator: " "), last: last)
    }

    static func initials(_ first: String) -> String {
        first.split(separator: " ").compactMap { $0.first.map { "\($0)." } }.joined(separator: " ")
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    static func accessedString(_ d: Date?, style: CitationStyle) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        switch style {
        case .mla: f.dateFormat = "d MMM. yyyy"
        default: f.dateFormat = "MMMM d, yyyy"
        }
        return f.string(from: d)
    }

    public static func bibliography(_ s: CitationSource, style: CitationStyle) -> String {
        let names = s.authors.map(split).filter { !$0.last.isEmpty }
        let title = s.title.trimmingCharacters(in: .whitespaces)
        switch style {
        case .apa:
            var authorPart = ""
            let formatted = names.map { "\($0.last), \(initials($0.first))".trimmingCharacters(in: .whitespaces) }
            if formatted.count == 1 { authorPart = formatted[0] }
            else if formatted.count == 2 { authorPart = "\(formatted[0]), & \(formatted[1])" }
            else if formatted.count > 2 { authorPart = formatted.dropLast().joined(separator: ", ") + ", & " + formatted.last! }
            var date = s.year.isEmpty ? "n.d." : s.year
            if !s.month.isEmpty && s.kind != .book && s.kind != .journal { date += ", \(s.month)" + (s.day.isEmpty ? "" : " \(s.day)") }
            var out = authorPart.isEmpty ? "\(title). (\(date))." : "\(authorPart) (\(date)). \(title)."
            if authorPart.isEmpty { out = "\(title). (\(date))." }
            switch s.kind {
            case .journal:
                var j = " \(s.container)"
                if !s.volume.isEmpty { j += ", \(s.volume)" }
                if !s.issue.isEmpty { j += "(\(s.issue))" }
                if !s.pages.isEmpty { j += ", \(s.pages)" }
                out += j + "."
            case .book:
                if !s.publisher.isEmpty { out += " \(s.publisher)." }
            case .website, .news:
                if !s.container.isEmpty { out += " \(s.container)." }
            }
            if !s.url.isEmpty { out += " \(s.url)" }
            return clean(out)

        case .mla:
            var authorPart = ""
            if names.count == 1 { authorPart = "\(names[0].last), \(names[0].first)." }
            else if names.count == 2 { authorPart = "\(names[0].last), \(names[0].first), and \(names[1].first) \(names[1].last)." }
            else if names.count > 2 { authorPart = "\(names[0].last), \(names[0].first), et al." }
            let titlePart = (s.kind == .book) ? "\(title)." : "\"\(title).\""
            var out = authorPart.isEmpty ? titlePart : "\(authorPart) \(titlePart)"
            var tail: [String] = []
            if !s.container.isEmpty { tail.append(s.container) }
            if !s.volume.isEmpty { tail.append("vol. \(s.volume)") }
            if !s.issue.isEmpty { tail.append("no. \(s.issue)") }
            if !s.publisher.isEmpty && s.publisher != s.container { tail.append(s.publisher) }
            let date = [s.day, s.month.isEmpty ? "" : String(s.month.prefix(3)) + (s.month.count > 3 ? "." : ""), s.year].filter { !$0.isEmpty }.joined(separator: " ")
            if !date.isEmpty { tail.append(date) }
            if !s.pages.isEmpty { tail.append("pp. \(s.pages)") }
            if !s.url.isEmpty { tail.append(s.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")) }
            if !tail.isEmpty { out += " " + tail.joined(separator: ", ") + "." }
            let acc = accessedString(s.accessed, style: .mla)
            if !acc.isEmpty && s.kind == .website { out += " Accessed \(acc)." }
            return clean(out)

        case .chicago:
            var authorPart = ""
            if names.count == 1 { authorPart = "\(names[0].last), \(names[0].first)." }
            else if names.count >= 2 {
                let rest = names.dropFirst().map { "\($0.first) \($0.last)" }
                authorPart = "\(names[0].last), \(names[0].first), " + (rest.count == 1 ? "and \(rest[0])." : rest.dropLast().joined(separator: ", ") + ", and \(rest.last!).")
            }
            let year = s.year.isEmpty ? "n.d." : s.year
            var out = authorPart.isEmpty ? "" : "\(authorPart) \(year). "
            out += (s.kind == .book) ? "\(title)." : "\"\(title).\""
            if authorPart.isEmpty { out += " \(year)." }
            switch s.kind {
            case .journal:
                out += " \(s.container)"
                if !s.volume.isEmpty { out += " \(s.volume)" }
                if !s.issue.isEmpty { out += " (\(s.issue))" }
                if !s.pages.isEmpty { out += ": \(s.pages)" }
                out += "."
            case .book:
                if !s.publisher.isEmpty { out += " \(s.publisher)." }
            case .website, .news:
                if !s.container.isEmpty { out += " \(s.container)." }
                if !s.month.isEmpty { out += " \(s.month)" + (s.day.isEmpty ? "" : " \(s.day)") + "." }
            }
            if !s.url.isEmpty { out += " \(s.url)." }
            return clean(out)
        }
    }

    public static func inText(_ s: CitationSource, style: CitationStyle, page: String = "") -> String {
        let names = s.authors.map(split).filter { !$0.last.isEmpty }
        var who: String
        switch names.count {
        case 0: who = s.title.isEmpty ? "Anonymous" : (style == .mla ? "\"\(s.title)\"" : s.title)
        case 1: who = names[0].last
        case 2: who = style == .apa ? "\(names[0].last) & \(names[1].last)" : "\(names[0].last) and \(names[1].last)"
        default: who = "\(names[0].last) et al."
        }
        let year = s.year.isEmpty ? "n.d." : s.year
        switch style {
        case .apa: return "(\(who), \(year)\(page.isEmpty ? "" : ", p. \(page)"))"
        case .mla: return "(\(who)\(page.isEmpty ? "" : " \(page)"))"
        case .chicago: return "(\(who) \(year)\(page.isEmpty ? "" : ", \(page)"))"
        }
    }

    static func clean(_ s: String) -> String {
        var out = s
        while out.contains("..") { out = out.replacingOccurrences(of: "..", with: ".") }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.replacingOccurrences(of: "?.", with: "?").replacingOccurrences(of: "!.", with: "!").trimmingCharacters(in: .whitespaces)
    }
}
