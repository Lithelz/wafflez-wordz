import Foundation

/// Purple underlines: tone, formality, politeness, confidence and inclusive language.
enum DeliveryRules {
    static var all: [WritingRule] { [hedging, formality, slang, politeness, inclusive] }

    static let hedging = PhraseRule(
        id: "hedging", category: .delivery,
        learnMore: "Hedging softens your message. A little is polite; too much can make you sound unsure.",
        when: { $0.goals.domain != .creative && $0.goals.domain != .casual },
        entries: [
            ("i just wanted to", ["I wanted to"], "Sound more confident", "\"Just\" can make a request sound apologetic."),
            ("just wanted to", ["wanted to"], "Sound more confident", "\"Just\" can make a request sound apologetic."),
            ("i was wondering if (you|we) could", ["could $1"], "Be more direct", "A direct question is clearer and still polite."),
            ("i was wondering if", ["I'd like to know if"], "Be more direct", "A direct question is clearer."),
            ("sorry to bother you,?", [""], "Sound more confident", "There's no need to apologize for reaching out."),
            ("i'm no expert,? but", [""], "Sound more confident", "Underselling yourself weakens your point."),
            ("i hope this makes sense", ["let me know if you have any questions"], "Sound more confident", "Offering to answer questions sounds more assured."),
            ("does that make sense\\?", ["Let me know if anything is unclear."], "Sound more confident", "This phrasing sounds more assured."),
            ("i feel like", ["I believe"], "Sound more confident", "\"I believe\" sounds more assured than \"I feel like\"."),
            ("i guess", ["I think"], "Sound more confident", "\"I guess\" can sound unsure."),
            ("kind of(?= [a-z]+(ed|ing|ly)?\\b)", [""], "Sound more confident", "\"Kind of\" softens your point. Remove it to sound sure."),
            ("sort of(?= [a-z]+)", [""], "Sound more confident", "\"Sort of\" softens your point."),
            ("if that's okay", [""], "Sound more confident", "You can make the request without asking permission."),
            ("hopefully(?=,? (this|that|we|it|you))", ["I expect"], "Sound more confident", "State what you expect instead of hoping."),
            ("i think that", ["I'm confident that", "I believe that"], "Sound more confident", "Owning your view makes it more persuasive."),
            ("(?:^|(?<=[.!?]\\s))maybe we could", ["Let's"], "Sound more confident", "A clear suggestion is easier to act on."),
        ]
    )

    static let slang = PhraseRule(
        id: "formality", category: .delivery,
        learnMore: "Text-speak can be hard to read and may look careless in professional writing.",
        when: { $0.goals.formality != .informal && $0.goals.domain != .casual },
        entries: [
            ("gonna", ["going to"], "Write it out", "\"Gonna\" is casual. \"Going to\" is clearer in writing."),
            ("wanna", ["want to"], "Write it out", "\"Wanna\" is casual."),
            ("gotta", ["have to", "need to"], "Write it out", "\"Gotta\" is casual."),
            ("kinda", ["kind of", "somewhat"], "Write it out", "\"Kinda\" is casual."),
            ("u(?= (are|can|will|should|could|have|need|know|guys))", ["you"], "Write it out", "Spelling out \"you\" is clearer."),
            ("ur(?= [a-z]{3,})", ["your"], "Write it out", "Spelling out \"your\" is clearer."),
            ("pls|plz", ["please"], "Write it out", "Spelling out \"please\" is more polite."),
            ("thx", ["thanks"], "Write it out", "Spelling out \"thanks\" is warmer."),
            ("cuz|coz", ["because"], "Write it out", "\"Because\" is clearer."),
            ("tho(?=[\\s.,!?]|$)", ["though"], "Write it out", "\"Though\" is clearer."),
            ("idk", ["I don't know"], "Write it out", "Not every reader knows this abbreviation."),
            ("imo", ["in my opinion"], "Write it out", "Not every reader knows this abbreviation."),
        ]
    )

    static let formality = PhraseRule(
        id: "formality", category: .delivery,
        learnMore: "Your goals are set to Formal, so casual words are flagged. Change goals to turn this off.",
        when: { $0.goals.formality == .formal },
        entries: [
            ("yeah", ["yes"], "Make it more formal", "\"Yes\" fits formal writing better."),
            ("nope", ["no"], "Make it more formal", "\"No\" fits formal writing better."),
            ("hey(?=[\\s,!])", ["Hello", "Hi"], "Make it more formal", "\"Hello\" fits formal writing better."),
            ("thanks(?! to)", ["thank you"], "Make it more formal", "\"Thank you\" is more formal."),
            ("okay|ok(?=[\\s.,!?])", ["all right", "acceptable"], "Make it more formal", "A more formal word fits better."),
            ("asap", ["as soon as possible"], "Make it more formal", "Write out abbreviations in formal writing."),
            ("btw", ["by the way", "also"], "Make it more formal", "Write out abbreviations in formal writing."),
            ("fyi", ["for your information", "note that"], "Make it more formal", "Write out abbreviations in formal writing."),
            ("a lot of", ["many", "much", "a great deal of"], "Make it more formal", "A more formal phrase fits better."),
            ("get rid of", ["remove", "eliminate"], "Make it more formal", "A more formal verb fits better."),
            ("figure out", ["determine", "work out"], "Make it more formal", "A more formal verb fits better."),
            ("pretty (good|bad|much|sure)", ["fairly $1"], "Make it more formal", "\"Fairly\" is more formal than \"pretty\"."),
            ("stuff", ["material", "items"], "Make it more formal", "A more precise word fits better."),
            ("kids", ["children"], "Make it more formal", "\"Children\" is more formal."),
        ]
    )

    static let politeness = PhraseRule(
        id: "politeness", category: .delivery,
        learnMore: "Direct requests can come across as demands. A small softener keeps things friendly without weakening your ask.",
        when: { $0.goals.domain == .email || $0.goals.domain == .business || $0.goals.domain == .general },
        entries: [
            ("i need you to", ["could you", "please"], "Make the request more polite", "This may come across as a demand."),
            ("you need to", ["please", "you'll want to"], "Make the request more polite", "This may come across as a demand."),
            ("you must", ["please", "be sure to"], "Make the request more polite", "This may come across as a demand."),
            ("asap(?=[\\s.!,]|$)", ["at your earliest convenience", "as soon as you can"], "Make the request more polite", "\"ASAP\" can feel pushy."),
            ("as per my last email", ["as I mentioned before", "to follow up on my last email"], "Make it friendlier", "This phrase often reads as irritated."),
            ("per my last email", ["as I mentioned before"], "Make it friendlier", "This phrase often reads as irritated."),
            ("why haven't you", ["could you let me know when you'll"], "Make it friendlier", "This can sound accusing."),
        ]
    )

    static let inclusive = PhraseRule(
        id: "inclusive", category: .delivery,
        learnMore: "Inclusive language avoids words that exclude people based on gender, ability, race or other traits.",
        entries: [
            ("chairman", ["chair", "chairperson"], "Use inclusive language", "\"Chair\" includes everyone."),
            ("chairmen", ["chairs"], "Use inclusive language", "\"Chairs\" includes everyone."),
            ("manpower", ["workforce", "staff"], "Use inclusive language", "\"Workforce\" includes everyone."),
            ("mankind", ["humankind", "humanity"], "Use inclusive language", "\"Humanity\" includes everyone."),
            ("man-made", ["artificial", "synthetic", "human-made"], "Use inclusive language", "A gender-neutral word works here."),
            ("man-hours", ["work hours", "person-hours"], "Use inclusive language", "A gender-neutral word works here."),
            ("(hey|hi|hello|thanks|thank you),? guys", ["$1, everyone", "$1, all"], "Use inclusive language", "\"Everyone\" includes the whole group."),
            ("you guys", ["you all", "everyone"], "Use inclusive language", "\"You all\" includes the whole group."),
            ("policeman|policewoman", ["police officer"], "Use inclusive language", "\"Police officer\" is gender-neutral."),
            ("fireman|firemen", ["firefighter"], "Use inclusive language", "\"Firefighter\" is gender-neutral."),
            ("mailman", ["mail carrier"], "Use inclusive language", "\"Mail carrier\" is gender-neutral."),
            ("businessman|businesswoman", ["businessperson", "professional"], "Use inclusive language", "A gender-neutral word works here."),
            ("businessmen", ["businesspeople", "professionals"], "Use inclusive language", "A gender-neutral word works here."),
            ("salesman", ["salesperson"], "Use inclusive language", "\"Salesperson\" is gender-neutral."),
            ("stewardess", ["flight attendant"], "Use inclusive language", "\"Flight attendant\" is gender-neutral."),
            ("freshman", ["first-year student"], "Use inclusive language", "\"First-year student\" is gender-neutral."),
            ("blacklist", ["blocklist", "denylist"], "Use inclusive language", "\"Blocklist\" is clearer and avoids racial associations."),
            ("blacklisted", ["blocked", "banned"], "Use inclusive language", "\"Blocked\" is clearer."),
            ("whitelist", ["allowlist"], "Use inclusive language", "\"Allowlist\" is clearer and avoids racial associations."),
            ("whitelisted", ["allowed", "approved"], "Use inclusive language", "\"Allowed\" is clearer."),
            ("master/slave", ["primary/replica", "leader/follower"], "Use inclusive language", "These terms are clearer and avoid references to slavery."),
            ("sanity check", ["quick check", "confidence check"], "Use inclusive language", "This avoids a reference to mental health."),
            ("grandfathered in", ["exempted", "carried over"], "Use inclusive language", "This term has roots in discriminatory voting laws."),
            ("handicapped", ["disabled", "accessible"], "Use inclusive language", "\"Disabled\" is the term most people prefer."),
            ("wheelchair-bound|confined to a wheelchair", ["uses a wheelchair"], "Use inclusive language", "Focus on the person, not a limitation."),
            ("illegal immigrants?", ["undocumented immigrant"], "Use inclusive language", "\"Undocumented\" describes status without labeling the person."),
            ("spirit animal", ["inspiration", "role model"], "Use inclusive language", "This term borrows from Indigenous traditions."),
            ("(that's|it's|this is|so) (crazy|insane)", ["$1 wild", "$1 surprising"], "Use inclusive language", "These words can stigmatize mental illness."),
            ("(that's|it's|this is|so) lame", ["$1 disappointing"], "Use inclusive language", "This word can be hurtful to people with disabilities."),
        ]
    )
}

/// Words a brand tone says to avoid.
struct BrandToneRule: WritingRule {
    let id = "brand-tone"
    let category = IssueCategory.delivery

    func check(_ ctx: RuleContext) -> [Suggestion] {
        var out: [Suggestion] = []
        for tone in ctx.config.brandTones where tone.enabled {
            for word in tone.wordsToAvoid where !word.trimmingCharacters(in: .whitespaces).isEmpty {
                let re = NSRegularExpression.ci("\\b" + TextUtils.escapeRegex(word.trimmingCharacters(in: .whitespaces)) + "\\b")
                for m in re.allMatches(ctx.text) {
                    out.append(Suggestion(
                        ruleID: id, category: category, range: m.range, original: ctx.sub(m.range), replacements: [],
                        title: "Off-brand for \(tone.name)",
                        explanation: "Your \(tone.name) brand tone avoids \"\(word)\". \(tone.summary)",
                        learnMore: "Brand tone traits: " + tone.traits.joined(separator: ", "),
                        offersAIRewrite: true
                    ))
                }
            }
        }
        return out
    }
}
