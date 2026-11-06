import AppKit
import ApplicationServices

/// Thin helpers over the macOS Accessibility API, which is how Wafflez reads and edits text in other apps.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static let systemWide = AXUIElementCreateSystemWide()

    // MARK: Reading

    static func raw(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        raw(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        guard let v = raw(el, name) else { return nil }
        if CFGetTypeID(v) == CFBooleanGetTypeID() { return CFBooleanGetValue((v as! CFBoolean)) }
        return (v as? NSNumber)?.boolValue
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let v = raw(el, name) as? [AnyObject] else { return [] }
        return v.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func axValue<T>(_ el: AXUIElement, _ name: String, _ type: AXValueType, _ initial: T) -> T? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = initial
        let ok = withUnsafeMutablePointer(to: &out) { AXValueGetValue(v as! AXValue, type, UnsafeMutableRawPointer($0)) }
        return ok ? out : nil
    }

    static func focusedElement() -> AXUIElement? {
        element(systemWide, kAXFocusedUIElementAttribute)
    }

    static func role(_ el: AXUIElement) -> String? { string(el, kAXRoleAttribute) }
    static func subrole(_ el: AXUIElement) -> String? { string(el, kAXSubroleAttribute) }
    static func value(_ el: AXUIElement) -> String? { string(el, kAXValueAttribute) }
    static func selectedText(_ el: AXUIElement) -> String? { string(el, kAXSelectedTextAttribute) }

    static func pid(_ el: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(el, &p)
        return p
    }

    static func selectedRange(_ el: AXUIElement) -> NSRange? {
        guard let r = axValue(el, kAXSelectedTextRangeAttribute, .cfRange, CFRange(location: 0, length: 0)) else { return nil }
        return NSRange(location: r.location, length: r.length)
    }

    /// Element frame in AX coordinates (origin at the top-left of the main screen).
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = axValue(el, kAXPositionAttribute, .cgPoint, CGPoint.zero),
              let s = axValue(el, kAXSizeAttribute, .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Screen rect of a text range, in AX coordinates.
    static func bounds(for range: NSRange, in el: AXUIElement) -> CGRect? {
        var cf = CFRange(location: range.location, length: range.length)
        guard let param = AXValueCreate(.cfRange, &cf) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return rect
    }

    /// Screen rects for a range, one per visual line, so wrapped text gets separate underlines.
    static func lineRects(for range: NSRange, in el: AXUIElement, text: String) -> [CGRect] {
        guard let whole = bounds(for: range, in: el) else { return [] }
        guard let first = bounds(for: NSRange(location: range.location, length: 1), in: el),
              first.height > 0, whole.height > first.height * 1.5 else { return [whole] }
        // The range wraps: measure each word and merge the ones on the same line.
        let ns = text as NSString
        guard range.location + range.length <= ns.length else { return [whole] }
        var rects: [CGRect] = []
        var i = range.location
        let end = range.location + range.length
        while i < end {
            while i < end, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: i)) ?? " ") { i += 1 }
            var j = i
            while j < end, !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: j)) ?? " ") { j += 1 }
            if j > i, let r = bounds(for: NSRange(location: i, length: j - i), in: el) {
                if let last = rects.last, abs(last.midY - r.midY) < first.height * 0.5 {
                    rects[rects.count - 1] = last.union(r)
                } else {
                    rects.append(r)
                }
            }
            i = j
        }
        return rects.isEmpty ? [whole] : rects
    }

    // MARK: Writing

    @discardableResult
    static func setSelectedRange(_ el: AXUIElement, _ range: NSRange) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let v = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, v) == .success
    }

    @discardableResult
    static func setSelectedText(_ el: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    static func isSettable(_ el: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el, name as CFString, &settable) == .success && settable.boolValue
    }

    // MARK: Classifying

    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]

    /// True for editable, non-password text fields.
    static func isEditableText(_ el: AXUIElement) -> Bool {
        if subrole(el) == "AXSecureTextField" || role(el) == "AXSecureTextField" { return false }
        guard let role = role(el) else { return false }
        if textRoles.contains(role) { return true }
        // Web content-editable regions in Chromium/Safari expose an editable ancestor.
        if raw(el, "AXEditableAncestor") != nil, isSettable(el, kAXSelectedTextRangeAttribute) { return true }
        return false
    }

    /// Chromium and Electron apps only build their accessibility tree when asked.
    static func enableWebAccessibility(pid: pid_t, bundleID: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
                                     "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
        if let bundleID, chromium.contains(bundleID) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    // MARK: Window text (context for AI Chat)

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        elements(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
    }

    static func title(_ el: AXUIElement) -> String? { string(el, kAXTitleAttribute) }

    /// Collects visible text from a window, depth-first, up to `limit` characters.
    static func text(in root: AXUIElement, limit: Int = 20000) -> String {
        var out = ""
        var visited = 0
        func walk(_ el: AXUIElement, depth: Int) {
            guard out.count < limit, depth < 40, visited < 4000 else { return }
            visited += 1
            let role = self.role(el) ?? ""
            if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" || role == "AXHeading" || role == "AXLink" {
                if let v = value(el), !v.trimmed.isEmpty {
                    out += v.trimmed + (role == "AXStaticText" || role == "AXLink" ? " " : "\n")
                } else if let t = title(el), !t.trimmed.isEmpty {
                    out += t.trimmed + " "
                }
            }
            if role == "AXSecureTextField" { return }
            for child in elements(el, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
            if role == "AXGroup" || role == "AXParagraph" { out += "\n" }
        }
        walk(root, depth: 0)
        return String(out.prefix(limit))
    }

    // MARK: Coordinates

    /// AX rects use a top-left origin; Cocoa windows use bottom-left.
    static func toCocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
