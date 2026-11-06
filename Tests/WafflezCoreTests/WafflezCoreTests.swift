import XCTest
@testable import WafflezCore

final class RuleTests: XCTestCase {
    let analyzer = TextAnalyzer()

    func suggestions(_ text: String, _ config: AnalyzerConfig = AnalyzerConfig()) -> [Suggestion] {
        analyzer.analyze(text, config: config, includeTone: false).suggestions
    }

    func first(_ text: String, rule: String, _ config: AnalyzerConfig = AnalyzerConfig()) -> Suggestion? {
        suggestions(text, config).first { $0.ruleID == rule }
    }

    func apply(_ s: Suggestion, to text: String) -> String {
        TextUtils.replacing(text, range: s.range, with: s.replacements.first ?? "")
    }

    func testRepeatedWord() throws {
        let text = "I went to the the store."
        let s = try XCTUnwrap(first(text, rule: "repeated-word"))
        XCTAssertEqual(apply(s, to: text), "I went to the store.")
    }

    func testArticle() throws {
        let text = "She ate a apple and an banana in a hour."
        let fixes = suggestions(text).filter { $0.ruleID == "a-an" }
        XCTAssertEqual(fixes.count, 3)
        XCTAssertNil(first("He has a university degree and an honest face.", rule: "a-an"))
    }

    func testLowercaseI() throws {
        let text = "Yesterday i think i'm late."
        let fixes = suggestions(text).filter { $0.ruleID == "lowercase-i" }
        XCTAssertEqual(fixes.count, 2)
    }

    func testSentenceCase() throws {
        let text = "This is fine. this is not fine at all."
        let s = try XCTUnwrap(first(text, rule: "sentence-case"))
        XCTAssertEqual(s.original, "this")
        XCTAssertEqual(s.replacements.first, "This")
        XCTAssertNil(first("We met Dr. smith today at noon.", rule: "sentence-case"))
    }

    func testConfusedWords() throws {
        var s = try XCTUnwrap(first("I could of done it.", rule: "confused-words"))
        XCTAssertEqual(s.replacements.first, "could have")
        s = try XCTUnwrap(first("This is better then that.", rule: "confused-words"))
        XCTAssertEqual(s.replacements.first, "better than")
        s = try XCTUnwrap(first("Its a nice day.", rule: "confused-words"))
        XCTAssertEqual(s.replacements.first, "It's a")
    }

    func testMissingApostrophe() throws {
        let s = try XCTUnwrap(first("I dont know.", rule: "missing-apostrophe"))
        XCTAssertEqual(s.replacements.first, "don't")
    }

    func testWordy() throws {
        let text = "We met in order to plan."
        let s = try XCTUnwrap(first(text, rule: "wordy"))
        XCTAssertEqual(apply(s, to: text), "We met to plan.")
        XCTAssertEqual(s.category, .clarity)
    }

    func testDeletionRemovesSpace() throws {
        let text = "We are in the process of hiring."
        let s = try XCTUnwrap(first(text, rule: "wordy"))
        XCTAssertEqual(apply(s, to: text), "We are hiring.")
    }

    func testPassive() throws {
        XCTAssertNotNil(first("The report was written by Sam.", rule: "passive-voice"))
        XCTAssertNil(first("I was tired after the trip.", rule: "passive-voice"))
    }

    func testLongSentence() throws {
        let long = Array(repeating: "word", count: 40).joined(separator: " ") + "."
        XCTAssertNotNil(first(long, rule: "long-sentence"))
    }

    func testIntensifier() throws {
        let s = try XCTUnwrap(first("The food was very good.", rule: "intensifier"))
        XCTAssertEqual(s.replacements.first, "great")
        XCTAssertEqual(s.category, .engagement)
    }

    func testHedgingAndInclusive() throws {
        XCTAssertEqual(first("I just wanted to check in.", rule: "hedging")?.category, .delivery)
        let s = try XCTUnwrap(first("Ask the chairman.", rule: "inclusive"))
        XCTAssertEqual(s.replacements.first, "chair")
        XCTAssertNotNil(first("Thanks guys!", rule: "inclusive"))
    }

    func testFormalityOnlyWhenFormal() throws {
        var c = AnalyzerConfig()
        XCTAssertNil(first("Yeah, that works for me.", rule: "formality", c))
        c.goals.formality = .formal
        XCTAssertNotNil(first("Yeah, that works for me.", rule: "formality", c))
        XCTAssertNotNil(first("I'm gonna call", rule: "formality"))
    }

    func testOkayNotInsideBook() throws {
        var c = AnalyzerConfig()
        c.goals.formality = .formal
        XCTAssertNil(suggestions("I read a book.", c).first { $0.original.lowercased() == "ok" })
    }

    func testDialect() throws {
        var c = AnalyzerConfig()
        c.dialect = .british
        var s = try XCTUnwrap(first("My favorite color is gray.", rule: "dialect-spelling", c))
        XCTAssertEqual(s.replacements.first, "favourite")
        c.dialect = .american
        s = try XCTUnwrap(first("We need to organise the centre.", rule: "dialect-spelling", c))
        XCTAssertEqual(s.replacements.first, "organize")
        c.dialect = .canadian
        let canadian = suggestions("I will organize the colour wheel.", c).filter { $0.ruleID == "dialect-spelling" }
        XCTAssertTrue(canadian.isEmpty)
    }

    func testStyleGuide() throws {
        var c = AnalyzerConfig()
        c.styleRules = [StyleRule(term: "e-mail", replacement: "email", note: "")]
        let s = try XCTUnwrap(first("Send an e-mail today.", rule: "style-guide", c))
        XCTAssertEqual(s.category, .styleGuide)
        XCTAssertEqual(s.replacements.first, "email")
    }

    func testDisabledRules() throws {
        var c = AnalyzerConfig()
        c.disabledRules = ["wordy"]
        XCTAssertNil(first("We met in order to plan.", rule: "wordy", c))
    }

    func testOxfordComma() throws {
        let text = "We bought apples, pears and plums."
        let s = try XCTUnwrap(first(text, rule: "oxford-comma"))
        XCTAssertEqual(apply(s, to: text), "We bought apples, pears, and plums.")
    }

    func testNoOverlaps() {
        let all = suggestions("Basically, i think we could of went in order to really good effect in the the end.")
        let wordLevel = all.filter { $0.ruleID != "long-sentence" }
        for (i, a) in wordLevel.enumerated() {
            for b in wordLevel[(i + 1)...] { XCTAssertFalse(a.overlaps(b), "\(a.ruleID) overlaps \(b.ruleID)") }
        }
    }

    func testURLsIgnored() {
        XCTAssertTrue(suggestions("Visit https://example.com/in-order-to-win now").filter { $0.ruleID == "wordy" }.isEmpty)
    }

    func testScoreAndStats() {
        let r = analyzer.analyze("This is a clean sentence. It reads well.", config: AnalyzerConfig())
        XCTAssertEqual(r.stats.words, 8)
        XCTAssertEqual(r.stats.sentences, 2)
        XCTAssertGreaterThan(r.score, 80)
    }
}

final class FeatureTests: XCTestCase {
    func testSentences() {
        let s = TextUtils.sentences(in: "Hello there. Mr. Smith is here! Is it 3.5 now? Yes")
        XCTAssertEqual(s.map(\.text), ["Hello there.", "Mr. Smith is here!", "Is it 3.5 now?", "Yes"])
    }

    func testTone() throws {
        let text = "Thank you so much for your help! I really appreciate it and I'm so glad we could work together. I'm looking forward to the next project, it's going to be great. Thanks again!"
        let tone = try XCTUnwrap(ToneDetector().detect(text))
        XCTAssertTrue(tone.tones.contains { $0.name == "Appreciative" || $0.name == "Friendly" })
        XCTAssertNil(ToneDetector().detect("Too short."))
    }

    func testAIDetector() {
        let ai = """
        In today's fast-paced world, it is important to note that technology plays a crucial role in our lives. Furthermore, it serves as a testament to human ingenuity and innovation. Moreover, we must navigate the complexities of this ever-evolving landscape with care. Additionally, organizations should leverage robust tools to foster seamless collaboration. In conclusion, embracing this multifaceted tapestry will unlock the potential of every team.
        """
        let human = """
        I missed the bus again. Honestly? Not the worst thing — I got coffee instead and called my sister, who's been sick all week. She sounded better. We laughed about the dog eating her slipper, which apparently happened twice. Anyway, I'll be late to the meeting, so tell Sam I'm sorry and I'll catch up on the notes tonight after dinner.
        """
        let a = AIDetector().analyze(ai)
        let h = AIDetector().analyze(human)
        XCTAssertTrue(a.enoughText)
        XCTAssertGreaterThan(a.percent, h.percent)
        XCTAssertGreaterThan(a.percent, 50)
        XCTAssertLessThan(h.percent, 30)
    }

    func testHumanizer() {
        let out = LocalHumanizer().humanize("In today's fast-paced world, we must leverage robust tools. It is not easy.")
        XCTAssertEqual(out, "We must use strong tools. It's not easy.")
    }

    func testOriginality() {
        let source = SourceDocument(title: "Essay", text: "The quick brown fox jumps over the lazy dog near the river bank every morning.")
        let mine = "Yesterday I wrote that the quick brown fox jumps over the lazy dog near the river, which was fun."
        let r = OriginalityChecker().check(mine, against: [source])
        XCTAssertEqual(r.matches.count, 1)
        XCTAssertGreaterThan(r.matchedPercent, 30)
        let quoted = "He said \"the quick brown fox jumps over the lazy dog near the river\" to me."
        XCTAssertEqual(OriginalityChecker().check(quoted, against: [source]).matches.count, 0)
    }

    func testAuthorship() {
        var l = AuthorshipLedger()
        l.start(with: "Hi")
        l.record(range: NSRange(location: 2, length: 0), replacement: " there", origin: .typed)
        l.record(range: NSRange(location: 8, length: 0), replacement: ". Pasted text", origin: .pasted, source: "https://example.com")
        l.record(range: NSRange(location: 0, length: 2), replacement: "Hello", origin: .wafflez)
        XCTAssertEqual(l.totalLength, ("Hello there. Pasted text" as NSString).length)
        let b = l.breakdown()
        XCTAssertEqual(b[.wafflez], 5)
        XCTAssertEqual(b[.typed], 6)
        XCTAssertEqual(b[.pasted], 13)
        XCTAssertNil(b[.existing])
        XCTAssertEqual(l.replay(events: l.events.count), "Hello there. Pasted text")
        XCTAssertEqual(l.replay(events: 1), "Hi there")
        let html = AuthorshipReport.html(title: "Test <doc>", text: "Hello there. Pasted text", ledger: l)
        XCTAssertTrue(html.contains("Test &lt;doc&gt;"))
    }

    func testCitations() {
        var s = CitationSource()
        s.kind = .website
        s.authors = ["Jane Doe", "John Smith"]
        s.title = "How Waffles Work"
        s.container = "Breakfast Journal"
        s.year = "2024"
        s.url = "https://example.com/waffles"
        XCTAssertEqual(CitationFormatter.bibliography(s, style: .apa), "Doe, J., & Smith, J. (2024). How Waffles Work. Breakfast Journal. https://example.com/waffles")
        XCTAssertEqual(CitationFormatter.inText(s, style: .apa), "(Doe & Smith, 2024)")
        XCTAssertEqual(CitationFormatter.inText(s, style: .mla, page: "4"), "(Doe and Smith 4)")
        XCTAssertTrue(CitationFormatter.bibliography(s, style: .mla).hasPrefix("Doe, Jane, and John Smith. \"How Waffles Work.\""))
    }

    func testJSONExtract() {
        let v = JSONValue.extract(from: "Here you go:\n```json\n{\"a\": [1, 2, {\"b\": \"}\"}]}\n```")
        XCTAssertEqual(v?["a"]?[2]?["b"]?.string, "}")
    }

    func testStreamAccumulator() {
        var acc = StreamAccumulator()
        let events = [
            #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hel"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"lo"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#,
        ]
        var text = ""
        for e in events { if let t = acc.apply(JSONValue.parse(e)!) { text += t } }
        XCTAssertEqual(text, "Hello")
        let blocks = acc.finishedBlocks()
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["signature"]?.string, "abc")
        XCTAssertEqual(blocks[1]["text"]?.string, "Hello")
        XCTAssertEqual(acc.stopReason, "end_turn")
    }

    func testRequestBody() throws {
        let client = ClaudeClient(apiKey: "test-key-not-real", model: .opus)
        let body = client.body(system: "s", messages: [ClaudeClient.textMessage("user", "hi")], maxTokens: 100,
                               effort: .low, tools: nil, schema: nil, stream: false)
        XCTAssertEqual(body["model"]?.string, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"]?.string, "default")
        XCTAssertEqual(body["output_config"]?["effort"]?.string, "low")
        XCTAssertNil(body["temperature"])
        let haiku = ClaudeClient(apiKey: "x", model: .haiku).body(system: "s", messages: [], maxTokens: 1, effort: .low, tools: nil, schema: nil, stream: false)
        XCTAssertNil(haiku["fallbacks"])
        XCTAssertThrowsError(try ClaudeClient(apiKey: " ", model: .opus).request(body))
    }

    func testEditLocator() {
        let text = "The cat sat. The cat sat."
        let edits = [AIEdit(original: "The cat sat.", replacement: "A cat sat.", category: .clarity, explanation: ""),
                     AIEdit(original: "The cat sat.", replacement: "One cat sat.", category: .clarity, explanation: "")]
        let s = EditLocator.suggestions(from: edits, in: text, ruleID: "ai")
        XCTAssertEqual(s.map(\.location), [0, 13])
    }
}
