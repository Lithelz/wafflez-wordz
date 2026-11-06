import Foundation

/// Swaps American and British-style spellings to match the chosen English (American, British, Canadian, Australian, Indian).
struct DialectRule: WritingRule {
    let id = "dialect-spelling"
    let category = IssueCategory.correctness

    enum Family { case our, ise, re, doubleL, misc, ogue, ence }

    /// Which spelling families use the non-American form in each dialect.
    static func usesBritish(_ family: Family, _ dialect: Dialect) -> Bool {
        switch dialect {
        case .american: return false
        case .british, .australian, .indian: return true
        case .canadian:
            // Canadian English: colour, centre, travelled, catalogue, defence — but organize.
            return family != .ise
        }
    }

    /// (American, British, family). Inflected forms are listed so whole words match.
    static let pairs: [(String, String, Family)] = {
        var list: [(String, String, Family)] = []
        let our = ["color", "favor", "honor", "behavior", "labor", "neighbor", "humor", "flavor", "rumor", "harbor", "vapor", "endeavor", "savor", "valor", "vigor", "armor", "odor", "parlor", "glamor"]
        for w in our {
            let b = String(w.dropLast(2)) + "our"
            list.append((w, b, .our))
            list.append((w + "s", b + "s", .our))
            list.append((w + "ed", b + "ed", .our))
            list.append((w + "ing", b + "ing", .our))
        }
        list += [("colorful", "colourful", .our), ("favorite", "favourite", .our), ("favorites", "favourites", .our),
                 ("favorable", "favourable", .our), ("honorable", "honourable", .our), ("behavioral", "behavioural", .our),
                 ("neighborhood", "neighbourhood", .our), ("neighborhoods", "neighbourhoods", .our),
                 ("humorous", "humorous", .our), ("flavorful", "flavourful", .our)]
        let ize = ["organiz", "realiz", "recogniz", "apologiz", "prioritiz", "criticiz", "emphasiz", "summariz",
                   "minimiz", "maximiz", "optimiz", "finaliz", "customiz", "categoriz", "memoriz", "authoriz",
                   "specializ", "standardiz", "visualiz", "characteriz", "familiariz", "personaliz", "utiliz",
                   "modernize".replacingOccurrences(of: "ze", with: "z"), "normaliz", "synchroniz", "civiliz", "localiz",
                   "mobiliz", "monetiz", "symboliz", "sympathiz", "harmoniz", "jeopardiz", "legaliz", "stabiliz", "energiz"]
        for stem in ize {
            let b = String(stem.dropLast()) + "s"
            for suffix in ["e", "es", "ed", "er", "ers", "ing", "ation", "ations"] {
                list.append((stem + suffix, b + suffix, .ise))
            }
        }
        for (a, b) in [("analyze", "analyse"), ("analyzed", "analysed"), ("analyzing", "analysing"),
                       ("paralyze", "paralyse"), ("catalyze", "catalyse")] {
            list.append((a, b, .ise))
        }
        for (a, b) in [("center", "centre"), ("centers", "centres"), ("centered", "centred"), ("theater", "theatre"),
                       ("theaters", "theatres"), ("liter", "litre"), ("liters", "litres"), ("fiber", "fibre"),
                       ("fibers", "fibres"), ("somber", "sombre"), ("caliber", "calibre"), ("luster", "lustre"),
                       ("kilometer", "kilometre"), ("kilometers", "kilometres"), ("centimeter", "centimetre"),
                       ("centimeters", "centimetres"), ("millimeter", "millimetre"), ("millimeters", "millimetres")] {
            list.append((a, b, .re))
        }
        for (a, b) in [("traveled", "travelled"), ("traveling", "travelling"), ("traveler", "traveller"),
                       ("travelers", "travellers"), ("canceled", "cancelled"), ("canceling", "cancelling"),
                       ("modeling", "modelling"), ("modeled", "modelled"), ("labeled", "labelled"), ("labeling", "labelling"),
                       ("fueled", "fuelled"), ("fueling", "fuelling"), ("leveled", "levelled"), ("leveling", "levelling"),
                       ("signaled", "signalled"), ("signaling", "signalling"), ("counselor", "counsellor"),
                       ("jewelry", "jewellery"), ("marvelous", "marvellous"), ("enrollment", "enrolment"),
                       ("fulfill", "fulfil"), ("fulfillment", "fulfilment"), ("skillful", "skilful"), ("willful", "wilful")] {
            list.append((a, b, .doubleL))
        }
        for (a, b) in [("catalog", "catalogue"), ("catalogs", "catalogues"), ("dialog", "dialogue"), ("analog", "analogue"),
                       ("monolog", "monologue"), ("prolog", "prologue")] {
            list.append((a, b, .ogue))
        }
        for (a, b) in [("defense", "defence"), ("offense", "offence"), ("pretense", "pretence")] {
            list.append((a, b, .ence))
        }
        for (a, b) in [("gray", "grey"), ("aluminum", "aluminium"), ("cozy", "cosy"), ("mold", "mould"),
                       ("plow", "plough"), ("skeptical", "sceptical"), ("skeptic", "sceptic"), ("pajamas", "pyjamas"),
                       ("aging", "ageing"), ("mustache", "moustache"), ("artifact", "artefact"),
                       ("cozier", "cosier"), ("donut", "doughnut"), ("smolder", "smoulder"), ("maneuver", "manoeuvre"),
                       ("pediatric", "paediatric"), ("anemia", "anaemia"), ("practicing", "practising")] {
            list.append((a, b, .misc))
        }
        return list.filter { $0.0 != $0.1 }
    }()

    /// One combined regex per direction, built once.
    static let lookupUS: [String: (String, Family)] = Dictionary(pairs.map { ($0.0, ($0.1, $0.2)) }, uniquingKeysWith: { a, _ in a })
    static let lookupUK: [String: (String, Family)] = Dictionary(pairs.map { ($0.1, ($0.0, $0.2)) }, uniquingKeysWith: { a, _ in a })

    func check(_ ctx: RuleContext) -> [Suggestion] {
        let dialect = ctx.config.dialect
        var out: [Suggestion] = []
        for w in ctx.words {
            if let hit = Self.lookupUS[w.lower], Self.usesBritish(hit.1, dialect) {
                out.append(make(w, to: hit.0, dialect: dialect))
            } else if let hit = Self.lookupUK[w.lower], !Self.usesBritish(hit.1, dialect) {
                out.append(make(w, to: hit.0, dialect: dialect))
            }
        }
        return out
    }

    private func make(_ w: WordSpan, to target: String, dialect: Dialect) -> Suggestion {
        Suggestion(
            ruleID: id, category: category, range: w.range, original: w.text,
            replacements: [TextUtils.matchCase(w.text, target)],
            title: "Match \(dialect.displayName) spelling",
            explanation: "\"\(target)\" is the usual spelling in \(dialect.displayName).",
            learnMore: "You can change which English you write in from Settings → General → I write in."
        )
    }
}

/// Gray underlines: your team's custom rules.
struct StyleGuideRule: WritingRule {
    let id = "style-guide"
    let category = IssueCategory.styleGuide

    func check(_ ctx: RuleContext) -> [Suggestion] {
        var out: [Suggestion] = []
        for rule in ctx.config.styleRules where rule.enabled {
            let term = rule.term.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }
            let pattern = "(?<![A-Za-z])" + TextUtils.escapeRegex(term) + "(?![A-Za-z])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: rule.caseSensitive ? [] : [.caseInsensitive]) else { continue }
            for m in re.allMatches(ctx.text) {
                let original = ctx.sub(m.range)
                // Already correct (e.g. rule only fixes capitalization).
                if original == rule.replacement { continue }
                out.append(Suggestion(
                    ruleID: id, category: category, range: m.range, original: original,
                    replacements: rule.replacement.isEmpty ? [] : [rule.replacement],
                    title: "Follow your style guide",
                    explanation: rule.note.isEmpty ? "Your style guide says to write \"\(rule.replacement)\" instead of \"\(term)\"." : rule.note,
                    learnMore: "Style guide rules are set in Wafflez Studio → Team → Style guide."
                ))
            }
        }
        return out
    }
}
