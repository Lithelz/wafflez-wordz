import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Models offered in Settings. The default is the most capable Opus.
public enum ClaudeModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .opus: return "Claude Opus 5.5 (best quality)"
        case .sonnet: return "Claude Sonnet 5.5 (balanced)"
        case .haiku: return "Claude Haiku 5.5 (fastest, lowest cost)"
        }
    }
    /// Haiku has no server-side fallback, so we don't send the parameter for it.
    var supportsServerFallback: Bool { self != .haiku }
}

/// How hard the model should think. Low for quick rewrites, higher for agents.
public enum AIEffort: String, Sendable {
    case low, medium, high
}

public enum ClaudeError: LocalizedError, Sendable {
    case missingKey
    case http(Int, String)
    case refusal(String?)
    case truncated
    case badResponse(String)
    case limitReached(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your Claude API key in Settings → AI to use AI features. Everything else works without one."
        case .http(let code, let message):
            switch code {
            case 401: return "Your Claude API key was rejected. Check it in Settings → AI."
            case 429: return "Claude is rate limiting requests right now. Wait a moment and try again."
            case 529, 503: return "Claude is busy right now. Try again in a moment."
            default: return "Claude returned an error (\(code)): \(message)"
            }
        case .refusal(let category):
            return "Claude declined this request" + (category.map { " (\($0))" } ?? "") + ". Try rephrasing it."
        case .truncated:
            return "The response was cut off. Try a shorter selection."
        case .badResponse(let why):
            return "Couldn't read Claude's reply: \(why)"
        case .limitReached(let why):
            return why
        }
    }
}

public struct ClaudeUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
}

public struct ClaudeResponse: Sendable {
    /// Raw content blocks, kept exactly as returned so multi-turn chats can send them back unchanged.
    public var content: [JSONValue]
    public var stopReason: String?
    public var usage: ClaudeUsage
    public var model: String?

    /// All text blocks joined together.
    public var text: String {
        content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined()
    }

    /// URLs from web search citations, if the request used web search.
    public var citedURLs: [(title: String, url: String)] {
        var out: [(String, String)] = []
        for block in content {
            for c in block["citations"]?.array ?? [] {
                if let url = c["url"]?.string, !out.contains(where: { $0.1 == url }) {
                    out.append((c["title"]?.string ?? url, url))
                }
            }
        }
        return out
    }
}

/// Talks to the Claude Messages API over HTTPS. The key is supplied by the user at runtime
/// (stored in the macOS Keychain by the app) and never written into source or logs.
public final class ClaudeClient: @unchecked Sendable {
    public var apiKey: String
    public var model: ClaudeModel
    public let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    public init(apiKey: String, model: ClaudeModel = .opus, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    // MARK: Request building

    public static func textMessage(_ role: String, _ text: String) -> JSONValue {
        ["role": .string(role), "content": [["type": "text", "text": .string(text)]]]
    }

    func body(system: String, messages: [JSONValue], maxTokens: Int, effort: AIEffort,
              tools: [JSONValue]?, schema: JSONValue?, stream: Bool) -> JSONValue {
        var o: [String: JSONValue] = [
            "model": .string(model.rawValue),
            "max_tokens": .number(Double(maxTokens)),
            "system": [["type": "text", "text": .string(system), "cache_control": ["type": "ephemeral"]]],
            "messages": .array(messages),
        ]
        var outputConfig: [String: JSONValue] = ["effort": .string(effort.rawValue)]
        if let schema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        o["output_config"] = .object(outputConfig)
        if let tools, !tools.isEmpty { o["tools"] = .array(tools) }
        if stream { o["stream"] = true }
        if model.supportsServerFallback { o["fallbacks"] = "default" }
        return .object(o)
    }

    func request(_ body: JSONValue) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.missingKey }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if model.supportsServerFallback {
            // If a safety classifier declines, Anthropic retries on its recommended fallback model.
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = body.encoded()
        return req
    }

    static func errorMessage(_ data: Data) -> String {
        if let v = try? JSONValue.parse(data), let m = v["error"]?["message"]?.string { return m }
        return String(data: data.prefix(300), encoding: .utf8) ?? "Unknown error"
    }

    // MARK: Non-streaming

    /// Sends a request. Handles `pause_turn` (long server-tool turns) by continuing automatically.
    public func send(system: String, messages: [JSONValue], maxTokens: Int = 16000, effort: AIEffort = .medium,
                     tools: [JSONValue]? = nil, schema: JSONValue? = nil) async throws -> ClaudeResponse {
        var convo = messages
        var collected: [JSONValue] = []
        var usage = ClaudeUsage()
        for _ in 0..<5 {
            let req = try request(body(system: system, messages: convo, maxTokens: maxTokens, effort: effort,
                                       tools: tools, schema: schema, stream: false))
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw ClaudeError.http(code, Self.errorMessage(data)) }
            let json = try JSONValue.parse(data)
            let content = json["content"]?.array ?? []
            usage.inputTokens += json["usage"]?["input_tokens"]?.int ?? 0
            usage.outputTokens += json["usage"]?["output_tokens"]?.int ?? 0
            let stop = json["stop_reason"]?.string
            collected += content
            // Always check the stop reason before using the content.
            if stop == "refusal" {
                throw ClaudeError.refusal(json["stop_details"]?["category"]?.string)
            }
            if stop == "pause_turn" {
                convo.append(["role": "assistant", "content": .array(content)])
                continue
            }
            if stop == "max_tokens" && schema != nil { throw ClaudeError.truncated }
            return ClaudeResponse(content: collected, stopReason: stop, usage: usage, model: json["model"]?.string)
        }
        return ClaudeResponse(content: collected, stopReason: "pause_turn", usage: usage, model: model.rawValue)
    }

    /// One-shot text helper.
    public func complete(system: String, prompt: String, maxTokens: Int = 16000, effort: AIEffort = .low) async throws -> String {
        let r = try await send(system: system, messages: [Self.textMessage("user", prompt)], maxTokens: maxTokens, effort: effort)
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Structured JSON output that follows `schema`.
    public func json(system: String, prompt: String, schema: JSONValue, maxTokens: Int = 16000, effort: AIEffort = .medium) async throws -> JSONValue {
        let r = try await send(system: system, messages: [Self.textMessage("user", prompt)], maxTokens: maxTokens, effort: effort, schema: schema)
        guard let v = JSONValue.extract(from: r.text) else { throw ClaudeError.badResponse("expected JSON") }
        return v
    }

    // MARK: Streaming

    /// Streams text as it is written. Returns the full response (with every content block rebuilt) at the end.
    public func stream(system: String, messages: [JSONValue], maxTokens: Int = 64000, effort: AIEffort = .medium,
                       tools: [JSONValue]? = nil, onText: @escaping @Sendable (String) -> Void) async throws -> ClaudeResponse {
        #if os(macOS)
        let req = try request(body(system: system, messages: messages, maxTokens: maxTokens, effort: effort,
                                   tools: tools, schema: nil, stream: true))
        let (bytes, resp) = try await session.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 {
            var data = Data()
            for try await b in bytes { data.append(b); if data.count > 4000 { break } }
            throw ClaudeError.http(code, Self.errorMessage(data))
        }
        var acc = StreamAccumulator()
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = JSONValue.parse(payload) else { continue }
            if let delta = acc.apply(event) { onText(delta) }
            if let err = event["error"]?["message"]?.string { throw ClaudeError.http(500, err) }
        }
        if acc.stopReason == "refusal" { throw ClaudeError.refusal(acc.refusalCategory) }
        return ClaudeResponse(content: acc.finishedBlocks(), stopReason: acc.stopReason, usage: acc.usage, model: acc.model)
        #else
        let r = try await send(system: system, messages: messages, maxTokens: min(maxTokens, 16000), effort: effort, tools: tools)
        onText(r.text)
        return r
        #endif
    }
}

/// Rebuilds content blocks from server-sent events so they can be replayed in later turns.
public struct StreamAccumulator: Sendable {
    public private(set) var blocks: [Int: [String: JSONValue]] = [:]
    var partialJSON: [Int: String] = [:]
    public private(set) var stopReason: String?
    public private(set) var refusalCategory: String?
    public private(set) var usage = ClaudeUsage()
    public private(set) var model: String?

    public init() {}

    /// Applies one event. Returns any new visible text.
    public mutating func apply(_ event: JSONValue) -> String? {
        switch event["type"]?.string {
        case "message_start":
            model = event["message"]?["model"]?.string
            usage.inputTokens = event["message"]?["usage"]?["input_tokens"]?.int ?? 0
        case "content_block_start":
            guard let i = event["index"]?.int, let block = event["content_block"]?.object else { return nil }
            blocks[i] = block
        case "content_block_delta":
            guard let i = event["index"]?.int, let delta = event["delta"] else { return nil }
            switch delta["type"]?.string {
            case "text_delta":
                let t = delta["text"]?.string ?? ""
                appendString(t, to: "text", at: i)
                return t
            case "thinking_delta":
                appendString(delta["thinking"]?.string ?? "", to: "thinking", at: i)
            case "signature_delta":
                appendString(delta["signature"]?.string ?? "", to: "signature", at: i)
            case "input_json_delta":
                partialJSON[i, default: ""] += delta["partial_json"]?.string ?? ""
            case "citations_delta":
                if let c = delta["citation"] {
                    var list = blocks[i]?["citations"]?.array ?? []
                    list.append(c)
                    blocks[i]?["citations"] = .array(list)
                }
            default: break
            }
        case "content_block_stop":
            if let i = event["index"]?.int, let raw = partialJSON[i] {
                blocks[i]?["input"] = JSONValue.parse(raw) ?? .object([:])
                partialJSON[i] = nil
            }
        case "message_delta":
            stopReason = event["delta"]?["stop_reason"]?.string ?? stopReason
            refusalCategory = event["delta"]?["stop_details"]?["category"]?.string ?? refusalCategory
            usage.outputTokens = event["usage"]?["output_tokens"]?.int ?? usage.outputTokens
        default: break
        }
        return nil
    }

    private mutating func appendString(_ piece: String, to key: String, at index: Int) {
        guard var block = blocks[index] else { return }
        block[key] = .string((block[key]?.string ?? "") + piece)
        blocks[index] = block
    }

    public func finishedBlocks() -> [JSONValue] {
        blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
    }
}
