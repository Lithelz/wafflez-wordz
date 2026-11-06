import AppKit
import WafflezCore

/// A click-through window laid over another app's text field that draws colored underlines.
@MainActor
final class UnderlineOverlay {
    struct Mark {
        var rect: CGRect        // screen (Cocoa) coordinates of the text
        var color: NSColor
        var highlighted: Bool
    }

    private let window: NSWindow
    private let view = UnderlineView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = view
    }

    /// Draws `marks` inside `area` (the text field's frame, in Cocoa coordinates).
    func show(_ marks: [Mark], in area: CGRect) {
        guard !marks.isEmpty, area.width > 0, area.height > 0 else { hide(); return }
        let frame = area.insetBy(dx: -4, dy: -6)
        if window.frame != frame { window.setFrame(frame, display: false) }
        view.marks = marks.map { m in
            var r = m.rect
            r.origin.x -= frame.minX
            r.origin.y -= frame.minY
            return Mark(rect: r, color: m.color, highlighted: m.highlighted)
        }
        view.needsDisplay = true
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        if window.isVisible { window.orderOut(nil) }
        view.marks = []
    }
}

final class UnderlineView: NSView {
    var marks: [UnderlineOverlay.Mark] = []

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        for m in marks {
            if m.highlighted {
                // Soft highlight behind the text while its card is open.
                m.color.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: m.rect.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3).fill()
            }
            let y = m.rect.minY + 0.5
            let path = NSBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: m.rect.minX + 1, y: y))
            path.line(to: NSPoint(x: m.rect.maxX - 1, y: y))
            m.color.withAlphaComponent(0.95).setStroke()
            path.stroke()
        }
    }
}
