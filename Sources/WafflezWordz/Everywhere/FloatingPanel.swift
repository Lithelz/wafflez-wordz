import AppKit
import SwiftUI

/// A borderless panel that floats over other apps without stealing focus from them.
final class FloatingPanel: NSPanel {
    var allowsKey: Bool
    var onClose: (() -> Void)?

    init(allowsKey: Bool, level: NSWindow.Level = .floating) {
        self.allowsKey = allowsKey
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = !allowsKey
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        onClose?()
    }
}

/// Hosts a SwiftUI view in a floating panel and keeps the panel sized to the content.
@MainActor
final class PanelHost<Content: View> {
    let panel: FloatingPanel
    private var hosting: NSHostingView<AnyView>?
    /// Which corner stays put when the content grows.
    var anchorTop = true

    init(allowsKey: Bool, level: NSWindow.Level = .floating) {
        panel = FloatingPanel(allowsKey: allowsKey, level: level)
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ content: Content, at origin: NSPoint, key: Bool = false) {
        let root = AnyView(
            content.reportSize { [weak self] size in
                MainActor.assumeIsolated { self?.resize(to: size) }
            }
            .fixedSize()
        )
        if let hosting {
            hosting.rootView = root
        } else {
            let h = NSHostingView(rootView: root)
            h.translatesAutoresizingMaskIntoConstraints = true
            panel.contentView = h
            hosting = h
        }
        let size = hosting?.fittingSize ?? NSSize(width: 300, height: 120)
        // `origin` is the top-left corner in screen coordinates.
        let frame = NSRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        panel.setFrame(clampToScreen(frame), display: true)
        if key && panel.allowsKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() { panel.orderOut(nil) }

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, panel.isVisible else { return }
        var f = panel.frame
        if abs(f.width - size.width) < 0.5 && abs(f.height - size.height) < 0.5 { return }
        if anchorTop { f.origin.y += f.height - size.height }
        f.size = size
        panel.setFrame(clampToScreen(f), display: true, animate: false)
    }

    private func clampToScreen(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var f = frame
        if f.maxX > visible.maxX - 6 { f.origin.x = visible.maxX - f.width - 6 }
        if f.minX < visible.minX + 6 { f.origin.x = visible.minX + 6 }
        if f.minY < visible.minY + 6 { f.origin.y = visible.minY + 6 }
        if f.maxY > visible.maxY - 6 { f.origin.y = visible.maxY - f.height - 6 }
        return f
    }
}
