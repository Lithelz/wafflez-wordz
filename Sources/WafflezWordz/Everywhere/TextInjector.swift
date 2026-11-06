import AppKit
import ApplicationServices
import Carbon

/// Puts text into other apps: first through Accessibility, then by pasting as a fallback.
enum TextInjector {
    enum Result { case replaced, pasted, failed }

    /// Replaces `range` in `element` with `replacement`, checking the text there still says `expected`.
    @MainActor
    static func replace(range: NSRange, expected: String, with replacement: String, in element: AXUIElement) async -> Result {
        guard let current = AX.value(element) else {
            return await pasteReplacing(range: range, with: replacement, in: element)
        }
        var target = range
        let ns = current as NSString
        if target.location + target.length > ns.length || ns.substring(with: target) != expected {
            // The text moved; look for the original nearby.
            let windowStart = max(0, range.location - 200)
            let windowLen = min(ns.length - windowStart, range.length + 400)
            let found = ns.range(of: expected, options: [], range: NSRange(location: windowStart, length: max(0, windowLen)))
            guard found.location != NSNotFound else { return .failed }
            target = found
        }
        let expectedAfter = ns.replacingCharacters(in: target, with: replacement)
        if AX.setSelectedRange(element, target), AX.setSelectedText(element, replacement) {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if AX.value(element) == expectedAfter { return .replaced }
        }
        return await pasteReplacing(range: target, with: replacement, in: element)
    }

    /// Inserts text at the cursor (or over the selection) in `element`.
    @MainActor
    static func insert(_ text: String, in element: AXUIElement?) async -> Result {
        if let element, AX.isSettable(element, kAXSelectedTextAttribute), AX.setSelectedText(element, text) {
            return .replaced
        }
        await paste(text)
        return .pasted
    }

    @MainActor
    private static func pasteReplacing(range: NSRange, with replacement: String, in element: AXUIElement) async -> Result {
        guard AX.setSelectedRange(element, range) else { return .failed }
        try? await Task.sleep(nanoseconds: 40_000_000)
        await paste(replacement)
        return .pasted
    }

    // MARK: Clipboard tricks (used for Google Docs and other canvas-based editors)

    /// Pastes text with ⌘V, then restores whatever was on the clipboard.
    @MainActor
    static func paste(_ text: String) async {
        let saved = ClipboardSnapshot.take()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        postKey(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 450_000_000)
        saved.restore()
    }

    /// Copies the current selection in the frontmost app with ⌘C and returns it, restoring the clipboard after.
    @MainActor
    static func copySelection() async -> String? {
        let saved = ClipboardSnapshot.take()
        let pb = NSPasteboard.general
        let before = pb.changeCount
        postKey(keyCode: UInt16(kVK_ANSI_C), flags: .maskCommand)
        var result: String?
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if pb.changeCount != before {
                result = pb.string(forType: .string)
                break
            }
        }
        saved.restore()
        return result
    }

    @MainActor
    static func selectAll() async {
        postKey(keyCode: UInt16(kVK_ANSI_A), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    static func postKey(keyCode: UInt16, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Saves every item on the clipboard so it can be put back after a paste.
struct ClipboardSnapshot {
    var items: [[NSPasteboard.PasteboardType: Data]]

    static func take() -> ClipboardSnapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
        return ClipboardSnapshot(items: items)
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (t, data) in dict { item.setData(data, forType: t) }
            return item
        }
        pb.writeObjects(objects)
    }
}
