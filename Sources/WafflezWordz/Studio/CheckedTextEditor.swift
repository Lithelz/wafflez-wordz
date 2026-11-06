import AppKit
import SwiftUI
import WafflezCore

/// NSTextView that knows where each edit came from (typed, pasted, AI, Wafflez) and shows suggestion cards on hover.
final class WafflezTextView: NSTextView {
    weak var controller: EditorController?
    var pendingOrigin: TextOrigin?
    var pendingSource: String?
    private var trackingArea: NSTrackingArea?

    /// Programmatic edit that goes through undo and the delegate like typing does.
    func replace(_ range: NSRange, with string: String, origin: TextOrigin) {
        let len = (self.string as NSString).length
        let safe = NSRange(location: min(range.location, len), length: min(range.length, max(0, len - range.location)))
        pendingOrigin = origin
        if shouldChangeText(in: safe, replacementString: string) {
            textStorage?.replaceCharacters(in: safe, with: string)
            didChangeText()
        }
        pendingOrigin = nil
    }

    override func paste(_ sender: Any?) {
        pendingOrigin = .pasted
        let pb = NSPasteboard.general
        let source = pb.string(forType: NSPasteboard.PasteboardType("org.chromium.source-url"))
            ?? pb.string(forType: NSPasteboard.PasteboardType("public.url"))
        pendingSource = source
        super.paste(sender)
        pendingOrigin = nil
        pendingSource = nil
        if let source { MainActor.assumeIsolated { controller?.pastedFrom(url: source) } }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        pendingOrigin = .pasted
        super.pasteAsPlainText(sender)
        pendingOrigin = nil
    }

    override func insertNewline(_ sender: Any?) {
        if MainActor.assumeIsolated({ controller?.handleSlashCommand() ?? false }) { return }
        super.insertNewline(sender)
        // Leaving a heading line goes back to body text.
        if let font = typingAttributes[.font] as? NSFont, font.pointSize > 17 {
            typingAttributes = Theme.editorAttributes
        }
    }

    // MARK: Hover cards

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func characterIndexUnderMouse(_ event: NSEvent) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: containerPoint, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard glyphRect.insetBy(dx: -1, dy: -2).contains(containerPoint) else { return nil }
        return lm.characterIndexForGlyph(at: glyph)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        MainActor.assumeIsolated {
            guard let controller else { return }
            if let i = characterIndexUnderMouse(event), let s = controller.suggestion(at: i) {
                controller.cancelHideCard()
                if controller.openCardID != s.id { controller.showCard(s) }
            } else {
                controller.scheduleHideCard()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        MainActor.assumeIsolated { controller?.scheduleHideCard() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard selectedRange().length > 0 else { return menu }
        let ai = NSMenuItem(title: "Rewrite with Wafflez", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in RewriteMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(rewriteFromMenu(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            sub.addItem(item)
        }
        ai.submenu = sub
        menu.insertItem(ai, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        return menu
    }

    @objc private func rewriteFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = RewriteMode(rawValue: raw) else { return }
        let range = selectedRange()
        let original = (string as NSString).substring(with: range)
        MainActor.assumeIsolated {
            guard let controller else { return }
            let s = controller.state.settings
            Task { @MainActor in
                do {
                    let out = try await controller.state.ai().rewrite(original, mode: mode, goals: controller.goals, dialect: s.dialect, brand: s.activeBrandTone)
                    if (self.string as NSString).length >= range.location + range.length,
                       (self.string as NSString).substring(with: range) == original {
                        self.replace(range, with: out, origin: .ai)
                    }
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't rewrite"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}

/// SwiftUI wrapper around WafflezTextView with a midnight look.
struct CheckedTextEditor: NSViewRepresentable {
    @ObservedObject var controller: EditorController
    var editable = true
    var inset = NSSize(width: 48, height: 32)

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = WafflezTextView(frame: .zero, textContainer: container)
        tv.isEditable = editable
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isContinuousSpellCheckingEnabled = false   // Wafflez does the checking
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = Theme.nsMidnight
        tv.insertionPointColor = Theme.nsSyrup
        tv.selectedTextAttributes = [.backgroundColor: NSColor(hex: "#7C8CFF").withAlphaComponent(0.35)]
        tv.textContainerInset = inset
        tv.typingAttributes = Theme.editorAttributes
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.appearance = NSAppearance(named: .darkAqua)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.nsMidnight
        scroll.scrollerStyle = .overlay
        scroll.documentView = tv
        scroll.appearance = NSAppearance(named: .darkAqua)

        controller.attach(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? WafflezTextView, tv.controller !== controller {
            controller.attach(tv)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let controller: EditorController
        init(_ c: EditorController) { controller = c }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacementString, let tv = textView as? WafflezTextView else { return true }
            controller.willChange(range: range, replacement: replacementString, origin: tv.pendingOrigin ?? .typed, source: tv.pendingSource)
            return true
        }

        func textDidChange(_ notification: Notification) {
            controller.didChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            controller.selectionChanged(tv.selectedRange())
        }
    }
}
