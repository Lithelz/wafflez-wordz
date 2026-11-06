import Foundation

/// Where a piece of text came from.
public enum TextOrigin: String, Codable, CaseIterable, Sendable, Identifiable {
    case typed, pasted, ai, wafflez, existing
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .typed: return "Typed by you"
        case .pasted: return "Pasted"
        case .ai: return "Written by AI"
        case .wafflez: return "Edited with Wafflez"
        case .existing: return "Already in the document"
        }
    }
    public var hexColor: String {
        switch self {
        case .typed: return "#3DDC97"
        case .pasted: return "#F5B942"
        case .ai: return "#B58CFF"
        case .wafflez: return "#5AA9FF"
        case .existing: return "#9AA3C7"
        }
    }
}

public struct OriginRun: Codable, Hashable, Sendable {
    public var origin: TextOrigin
    public var length: Int
    public var source: String?
}

/// One recorded edit, used for the replay.
public struct EditEvent: Codable, Hashable, Sendable {
    public var time: TimeInterval   // seconds since recording started
    public var location: Int
    public var deleted: Int
    public var inserted: String
    public var origin: TextOrigin
}

/// Records where every character in a document came from, plus a replay log.
/// Only covers writing done while recording was on, so it can't vouch for text after the fact.
public struct AuthorshipLedger: Codable, Hashable, Sendable {
    public var runs: [OriginRun] = []
    public var events: [EditEvent] = []
    public var initialText: String = ""
    public var startedAt: Date = Date()
    public var isRecording: Bool = false
    public var pasteSources: [String] = []

    public init() {}

    /// Starts recording. Text already in the document is marked "existing".
    public mutating func start(with currentText: String) {
        let len = (currentText as NSString).length
        runs = len > 0 ? [OriginRun(origin: .existing, length: len, source: nil)] : []
        events = []
        initialText = currentText
        startedAt = Date()
        isRecording = true
        pasteSources = []
    }

    public var totalLength: Int { runs.reduce(0) { $0 + $1.length } }

    /// Call for every edit: `range` in the old text is replaced by `replacement`.
    public mutating func record(range: NSRange, replacement: String, origin: TextOrigin, source: String? = nil, at time: Date = Date()) {
        guard isRecording else { return }
        let insertLen = (replacement as NSString).length
        let loc = max(0, min(range.location, totalLength))
        let delLen = max(0, min(range.length, totalLength - loc))

        // Split runs and rebuild with the edit applied.
        var newRuns: [OriginRun] = []
        var pos = 0
        var inserted = false
        for run in runs {
            let rStart = pos
            let rEnd = pos + run.length
            pos = rEnd
            // Part before the edit.
            if rStart < loc {
                newRuns.append(OriginRun(origin: run.origin, length: min(rEnd, loc) - rStart, source: run.source))
            }
            if !inserted && rEnd >= loc && insertLen > 0 && rStart <= loc {
                newRuns.append(OriginRun(origin: origin, length: insertLen, source: source))
                inserted = true
            }
            // Part after the deleted span.
            let delEnd = loc + delLen
            if rEnd > delEnd {
                let s = max(rStart, delEnd)
                newRuns.append(OriginRun(origin: run.origin, length: rEnd - s, source: run.source))
            }
        }
        if !inserted && insertLen > 0 {
            newRuns.append(OriginRun(origin: origin, length: insertLen, source: source))
        }
        runs = Self.coalesce(newRuns)
        if let source, origin == .pasted, !pasteSources.contains(source) { pasteSources.append(source) }

        let t = time.timeIntervalSince(startedAt)
        // Merge consecutive single keystrokes into one event to keep the log small.
        if origin == .typed, delLen == 0, let last = events.last, last.origin == .typed, last.deleted == 0,
           last.location + (last.inserted as NSString).length == loc, t - last.time < 1.5 {
            events[events.count - 1].inserted += replacement
            events[events.count - 1].time = t
        } else {
            events.append(EditEvent(time: t, location: loc, deleted: delLen, inserted: replacement, origin: origin))
        }
    }

    static func coalesce(_ runs: [OriginRun]) -> [OriginRun] {
        var out: [OriginRun] = []
        for r in runs where r.length > 0 {
            if let last = out.last, last.origin == r.origin, last.source == r.source {
                out[out.count - 1].length += r.length
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Character counts per origin.
    public func breakdown() -> [TextOrigin: Int] {
        var d: [TextOrigin: Int] = [:]
        for r in runs { d[r.origin, default: 0] += r.length }
        return d
    }

    public func percentages() -> [(TextOrigin, Double)] {
        let total = max(1, totalLength)
        let b = breakdown()
        return TextOrigin.allCases.compactMap { o in
            guard let n = b[o], n > 0 else { return nil }
            return (o, Double(n) / Double(total) * 100)
        }
    }

    /// UTF-16 ranges for each origin, in order.
    public func originRanges() -> [(NSRange, TextOrigin)] {
        var pos = 0
        return runs.map { r in
            defer { pos += r.length }
            return (NSRange(location: pos, length: r.length), r.origin)
        }
    }

    /// The document as it looked after `count` events.
    public func replay(events count: Int) -> String {
        var text = initialText as NSString
        for e in events.prefix(count) {
            let loc = min(e.location, text.length)
            let len = min(e.deleted, text.length - loc)
            text = text.replacingCharacters(in: NSRange(location: loc, length: len), with: e.inserted) as NSString
        }
        return text as String
    }

    public var duration: TimeInterval { events.last?.time ?? 0 }
}

// MARK: - Shareable report

public enum AuthorshipReport {
    /// A self-contained HTML page with the breakdown, color-coded text and a replay slider.
    /// Open it in any browser; no account needed.
    public static func html(title: String, text: String, ledger: AuthorshipLedger, generated: Date = Date()) -> String {
        let ns = text as NSString
        var body = ""
        for (range, origin) in ledger.originRanges() where range.location + range.length <= ns.length {
            let chunk = escape(ns.substring(with: range)).replacingOccurrences(of: "\n", with: "<br>")
            body += "<span class=\"o-\(origin.rawValue)\" title=\"\(origin.displayName)\">\(chunk)</span>"
        }
        let bars = ledger.percentages().map { o, p in
            "<div class=\"row\"><span class=\"dot\" style=\"background:\(o.hexColor)\"></span><span class=\"lbl\">\(o.displayName)</span><span class=\"pct\">\(String(format: "%.0f", p))%</span><div class=\"bar\"><div style=\"width:\(String(format: "%.1f", p))%;background:\(o.hexColor)\"></div></div></div>"
        }.joined()
        let eventsJSON: String = {
            let enc = JSONEncoder()
            let data = (try? enc.encode(ledger.events)) ?? Data("[]".utf8)
            return (String(data: data, encoding: .utf8) ?? "[]").replacingOccurrences(of: "</", with: "<\\/")
        }()
        let initialJSON: String = {
            let data = (try? JSONEncoder().encode([ledger.initialText])) ?? Data("[\"\"]".utf8)
            return (String(data: data, encoding: .utf8) ?? "[\"\"]").replacingOccurrences(of: "</", with: "<\\/")
        }()
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        let sources = ledger.pasteSources.isEmpty ? "" :
            "<h2>Pasted from</h2><ul>" + ledger.pasteSources.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
        let css = TextOrigin.allCases.map { ".o-\($0.rawValue){border-bottom:2px solid \($0.hexColor);background:\($0.hexColor)1f}" }.joined()

        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Authorship report · \(escape(title))</title>
        <style>
        :root{color-scheme:dark}body{margin:0;background:#0B1020;color:#E6E9F5;font:15px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif}
        main{max-width:820px;margin:0 auto;padding:40px 20px}h1{font-size:26px;margin:0 0 4px}h2{font-size:16px;color:#9AA3C7;margin:28px 0 10px;font-weight:600}
        .sub{color:#9AA3C7;font-size:13px}.card{background:#141B36;border:1px solid #273059;border-radius:14px;padding:18px 20px;margin-top:16px}
        .row{display:grid;grid-template-columns:14px 180px 50px 1fr;align-items:center;gap:8px;margin:6px 0}.dot{width:10px;height:10px;border-radius:50%}
        .pct{text-align:right;font-variant-numeric:tabular-nums}.bar{height:8px;background:#0B1020;border-radius:4px;overflow:hidden}.bar div{height:100%}
        .doc{white-space:normal;word-wrap:break-word}\(css)
        #replay{white-space:pre-wrap;min-height:120px}input[type=range]{width:100%;accent-color:#F5B942}
        .brand{color:#F5B942;font-weight:700}footer{color:#6F78A0;font-size:12px;margin-top:30px}
        </style></head><body><main>
        <div class="sub"><span class="brand">🧇 Wafflez Wordz</span> · Authorship report</div>
        <h1>\(escape(title))</h1>
        <div class="sub">Generated \(df.string(from: generated)) · \(ledger.events.count) recorded edits over \(Int(ledger.duration / 60)) min</div>
        <div class="card">\(bars)</div>
        \(sources)
        <h2>Document, colored by origin</h2><div class="card doc">\(body)</div>
        <h2>Replay</h2><div class="card"><input id="slider" type="range" min="0" max="\(ledger.events.count)" value="\(ledger.events.count)"><div class="sub" id="pos"></div><div id="replay"></div></div>
        <footer>Authorship only covers writing done while recording was on in Wafflez Studio. It records the writing process; it is not an AI detector.</footer>
        </main><script>
        const ev=\(eventsJSON);const init=\(initialJSON)[0];const s=document.getElementById('slider'),out=document.getElementById('replay'),pos=document.getElementById('pos');
        function render(n){let t=init;for(let i=0;i<n;i++){const e=ev[i];t=t.slice(0,e.location)+e.inserted+t.slice(e.location+e.deleted);}out.textContent=t;pos.textContent='Step '+n+' of '+ev.length+(n>0?' · '+Math.round(ev[n-1].time)+'s':'');}
        s.addEventListener('input',()=>render(+s.value));render(+s.value);
        </script></body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
