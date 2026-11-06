import Foundation

/// Blue underlines: wordy, unclear or hard-to-read writing.
enum ClarityRules {
    static var all: [WritingRule] { [wordy, filler, PassiveVoiceRule(), LongSentenceRule()] }

    static let wordy = PhraseRule(
        id: "wordy", category: .clarity,
        learnMore: "Concise writing respects your reader's time. Short, direct phrases are easier to scan.",
        entries: [
            ("in order to", ["to"], "Remove wordiness", "\"To\" says the same thing in fewer words."),
            ("due to the fact that", ["because"], "Remove wordiness", "\"Because\" is shorter and clearer."),
            ("owing to the fact that", ["because"], "Remove wordiness", "\"Because\" is shorter and clearer."),
            ("in light of the fact that", ["because"], "Remove wordiness", "\"Because\" is shorter and clearer."),
            ("despite the fact that", ["although"], "Remove wordiness", "\"Although\" is shorter."),
            ("in spite of the fact that", ["although"], "Remove wordiness", "\"Although\" is shorter."),
            ("at this point in time", ["now"], "Remove wordiness", "\"Now\" is simpler."),
            ("at the present time", ["now", "currently"], "Remove wordiness", "\"Now\" is simpler."),
            ("in the event that", ["if"], "Remove wordiness", "\"If\" says the same thing."),
            ("for the purpose of", ["to", "for"], "Remove wordiness", "A shorter phrase works here."),
            ("a large number of", ["many"], "Remove wordiness", "\"Many\" is more concise."),
            ("a great deal of", ["much", "a lot of"], "Remove wordiness", "A shorter phrase works here."),
            ("the majority of", ["most"], "Remove wordiness", "\"Most\" is more concise."),
            ("a majority of", ["most"], "Remove wordiness", "\"Most\" is more concise."),
            ("is able to", ["can"], "Remove wordiness", "\"Can\" is shorter."),
            ("are able to", ["can"], "Remove wordiness", "\"Can\" is shorter."),
            ("has the ability to", ["can"], "Remove wordiness", "\"Can\" is shorter."),
            ("have the ability to", ["can"], "Remove wordiness", "\"Can\" is shorter."),
            ("in the near future", ["soon"], "Remove wordiness", "\"Soon\" is simpler."),
            ("prior to", ["before"], "Simplify", "\"Before\" is plainer."),
            ("subsequent to", ["after"], "Simplify", "\"After\" is plainer."),
            ("with regard to", ["about", "regarding"], "Simplify", "\"About\" is plainer."),
            ("with respect to", ["about", "regarding"], "Simplify", "\"About\" is plainer."),
            ("in regard to", ["about", "regarding"], "Simplify", "\"About\" is plainer."),
            ("in relation to", ["about"], "Simplify", "\"About\" is plainer."),
            ("in close proximity to", ["near"], "Remove wordiness", "\"Near\" is shorter."),
            ("each and every", ["every"], "Remove redundancy", "\"Each and every\" repeats itself."),
            ("first and foremost", ["first"], "Remove redundancy", "\"First\" is enough."),
            ("absolutely essential", ["essential"], "Remove redundancy", "Essential already means absolutely necessary."),
            ("basic fundamentals", ["fundamentals"], "Remove redundancy", "Fundamentals are already basic."),
            ("end result", ["result"], "Remove redundancy", "A result is already the end."),
            ("final outcome", ["outcome"], "Remove redundancy", "An outcome is already final."),
            ("past history", ["history"], "Remove redundancy", "History is already in the past."),
            ("future plans", ["plans"], "Remove redundancy", "Plans are already about the future."),
            ("advance planning", ["planning"], "Remove redundancy", "Planning already happens in advance."),
            ("completely finished", ["finished"], "Remove redundancy", "Finished is already complete."),
            ("free gift", ["gift"], "Remove redundancy", "Gifts are already free."),
            ("join together", ["join"], "Remove redundancy", "\"Join\" already means to bring together."),
            ("repeat again", ["repeat"], "Remove redundancy", "\"Repeat\" already means again."),
            ("revert back", ["revert"], "Remove redundancy", "\"Revert\" already means go back."),
            ("whether or not", ["whether"], "Remove wordiness", "\"Whether\" usually works on its own."),
            ("it is important to note that", ["note that"], "Remove wordiness", "Get to the point faster."),
            ("it should be noted that", ["note that"], "Remove wordiness", "Get to the point faster."),
            ("on a daily basis", ["daily"], "Remove wordiness", "\"Daily\" is shorter."),
            ("on a regular basis", ["regularly"], "Remove wordiness", "\"Regularly\" is shorter."),
            ("on a weekly basis", ["weekly"], "Remove wordiness", "\"Weekly\" is shorter."),
            ("make a decision", ["decide"], "Use a stronger verb", "\"Decide\" is more direct."),
            ("come to a conclusion", ["conclude"], "Use a stronger verb", "\"Conclude\" is more direct."),
            ("give consideration to", ["consider"], "Use a stronger verb", "\"Consider\" is more direct."),
            ("take into consideration", ["consider"], "Use a stronger verb", "\"Consider\" is more direct."),
            ("make an assumption", ["assume"], "Use a stronger verb", "\"Assume\" is more direct."),
            ("conduct an investigation", ["investigate"], "Use a stronger verb", "\"Investigate\" is more direct."),
            ("provide assistance", ["help"], "Use a stronger verb", "\"Help\" is more direct."),
            ("until such time as", ["until"], "Remove wordiness", "\"Until\" is enough."),
            ("at all times", ["always"], "Remove wordiness", "\"Always\" is shorter."),
            ("in an effort to", ["to"], "Remove wordiness", "\"To\" is enough."),
            ("for the most part", ["mostly"], "Remove wordiness", "\"Mostly\" is shorter."),
            ("there is no doubt that", ["undoubtedly"], "Remove wordiness", "One word does the job."),
            ("with the exception of", ["except"], "Remove wordiness", "\"Except\" is shorter."),
            ("in the process of", [""], "Remove wordiness", "This phrase usually adds nothing."),
            ("a number of", ["several", "some"], "Be more specific", "\"Several\" or a real number is clearer."),
            ("an adequate number of", ["enough"], "Remove wordiness", "\"Enough\" is shorter."),
            ("utilize", ["use"], "Simplify", "\"Use\" is plainer and means the same thing."),
            ("utilizes", ["uses"], "Simplify", "\"Uses\" is plainer."),
            ("utilized", ["used"], "Simplify", "\"Used\" is plainer."),
            ("utilizing", ["using"], "Simplify", "\"Using\" is plainer."),
            ("utilization", ["use"], "Simplify", "\"Use\" is plainer."),
            ("commence", ["begin", "start"], "Simplify", "\"Begin\" is plainer."),
            ("ascertain", ["find out", "learn"], "Simplify", "\"Find out\" is plainer."),
            ("approximately", ["about"], "Simplify", "\"About\" is plainer."),
            ("very unique", ["unique"], "Remove redundancy", "Unique can't be more or less unique."),
            ("in terms of", ["for", "in"], "Simplify", "A shorter word is often clearer."),
        ]
    )

    static let filler = PhraseRule(
        id: "filler", category: .clarity,
        learnMore: "Filler words take up space without adding meaning. Removing them makes your point land harder.",
        entries: [
            ("basically", [""], "Remove the filler word", "\"Basically\" rarely adds meaning."),
            ("actually(?=\\s)", [""], "Remove the filler word", "\"Actually\" can often go."),
            ("literally", [""], "Remove the filler word", "\"Literally\" is often used for emphasis and can go."),
            ("totally", [""], "Remove the filler word", "\"Totally\" rarely adds meaning."),
            ("essentially", [""], "Remove the filler word", "\"Essentially\" can often go."),
            ("needless to say,?", [""], "Remove the filler phrase", "If it's needless to say, you can skip it."),
            ("as a matter of fact,?", [""], "Remove the filler phrase", "This phrase rarely adds meaning."),
        ]
    )
}

struct PassiveVoiceRule: WritingRule {
    let id = "passive-voice"
    let category = IssueCategory.clarity

    static let irregular = "written|done|made|given|taken|seen|known|shown|told|found|built|sent|held|kept|left|lost|meant|paid|put|read|said|sold|thought|brought|bought|caught|taught|chosen|driven|eaten|forgotten|forgiven|frozen|hidden|ridden|spoken|stolen|sworn|torn|worn|woven|begun|drunk|rung|sung|sunk|swum|broken|beaten|bitten|blown|drawn|grown|thrown|flown|shaken|undertaken|overseen|set|cut|hit|hurt|shut|split|spread|led|fed|met|won|struck|understood|withdrawn"
    static let re = NSRegularExpression.ci("\\b(am|is|are|was|were|be|been|being)\\s+(?:(?:not|also|often|always|never|usually|already|then)\\s+)?([a-z]+ed|" + irregular + ")\\b(\\s+by\\b)?")
    /// Words ending in -ed that usually work as adjectives.
    static let adjectives: Set<String> = [
        "interested", "tired", "excited", "based", "married", "supposed", "used", "concerned", "pleased",
        "worried", "located", "scared", "bored", "related", "involved", "satisfied", "surprised",
        "confused", "frustrated", "disappointed", "amazed", "annoyed", "ashamed", "embarrassed",
        "exhausted", "relaxed", "prepared", "qualified", "experienced", "talented", "detailed",
        "advanced", "complicated", "committed", "dedicated", "focused", "motivated", "organized",
        "allowed", "required", "needed", "expected", "designed", "limited", "connected", "aged",
        "red", "bed", "shed", "need", "feed", "seed", "speed", "proceed", "exceed", "succeed", "indeed",
        "hundred", "sacred", "naked", "wicked", "rugged", "crooked", "ragged", "kindred", "excited",
        "thrilled", "delighted", "overwhelmed", "stressed", "engaged", "closed", "opened", "finished",
    ]

    func check(_ ctx: RuleContext) -> [Suggestion] {
        if ctx.config.goals.domain == .academic || ctx.config.goals.domain == .technical {
            // Passive voice is normal in methods sections; only flag the clear "by" cases.
            return check(ctx, requireBy: true)
        }
        return check(ctx, requireBy: false)
    }

    private func check(_ ctx: RuleContext, requireBy: Bool) -> [Suggestion] {
        Self.re.allMatches(ctx.text).compactMap { m in
            let participle = ctx.sub(m.range(at: 2)).lowercased()
            let hasBy = m.range(at: 3).location != NSNotFound
            if requireBy && !hasBy { return nil }
            if !hasBy && Self.adjectives.contains(participle) { return nil }
            let r = NSRange(location: m.range.location, length: m.range(at: 2).location + m.range(at: 2).length - m.range.location)
            return Suggestion(
                ruleID: id, category: category, range: r, original: ctx.sub(r), replacements: [],
                title: "Consider the active voice",
                explanation: hasBy
                    ? "This sentence is in the passive voice. Putting the doer first (the part after \"by\") usually reads more clearly."
                    : "This sentence may be in the passive voice. Naming who does the action can make it clearer.",
                learnMore: "Passive: \"The report was written by Sam.\" Active: \"Sam wrote the report.\"",
                offersAIRewrite: true
            )
        }
    }
}

struct LongSentenceRule: WritingRule {
    let id = "long-sentence"
    let category = IssueCategory.clarity

    func check(_ ctx: RuleContext) -> [Suggestion] {
        let limit = max(15, ctx.config.maxSentenceWords)
        return ctx.sentences.compactMap { s in
            guard s.wordCount > limit else { return nil }
            return Suggestion(
                ruleID: id, category: category, range: s.range, original: s.text, replacements: [],
                title: "Long sentence",
                explanation: "This sentence has \(s.wordCount) words. Splitting it into two or three shorter sentences will make it easier to follow.",
                learnMore: "Most readers find sentences under 25 words easiest to follow.",
                offersAIRewrite: true
            )
        }
    }
}
