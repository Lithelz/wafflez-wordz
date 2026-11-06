import AppKit
import SwiftUI
import WafflezCore

/// Midnight theme, tuned to sit naturally beside macOS dark mode.
enum Theme {
    // Backgrounds
    static let midnight = Color(hex: "#0B1020")      // window background
    static let surface = Color(hex: "#121933")       // sidebars and panels
    static let elevated = Color(hex: "#1A2244")      // cards
    static let raised = Color(hex: "#222B52")        // hover / selected
    static let stroke = Color(hex: "#2A3460")
    // Text
    static let text = Color(hex: "#E6E9F5")
    static let textSecondary = Color(hex: "#9AA3C7")
    static let textTertiary = Color(hex: "#6F78A0")
    // Accents: syrup gold and moonlight indigo
    static let syrup = Color(hex: "#F5B942")
    static let indigo = Color(hex: "#7C8CFF")
    static let success = Color(hex: "#3DDC97")
    static let danger = Color(hex: "#FF6B81")

    static let accentGradient = LinearGradient(colors: [Color(hex: "#F5B942"), Color(hex: "#F08A4B")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let midnightGradient = LinearGradient(colors: [Color(hex: "#0B1020"), Color(hex: "#131A3A")], startPoint: .top, endPoint: .bottom)

    static func color(_ c: IssueCategory) -> Color { Color(hex: c.hexColor) }
    static func nsColor(_ c: IssueCategory) -> NSColor { NSColor(hex: c.hexColor) }
    static func color(_ o: TextOrigin) -> Color { Color(hex: o.hexColor) }

    static let nsMidnight = NSColor(hex: "#0B1020")
    static let nsSurface = NSColor(hex: "#121933")
    static let nsText = NSColor(hex: "#E6E9F5")
    static let nsSyrup = NSColor(hex: "#F5B942")

    static let editorFont = NSFont.systemFont(ofSize: 16)
    static var editorAttributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 5
        p.paragraphSpacing = 10
        return [.font: editorFont, .foregroundColor: nsText, .paragraphStyle: p]
    }
}

extension Color {
    init(hex: String) {
        let ns = NSColor(hex: hex)
        self.init(nsColor: ns)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255; a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Reusable pieces

/// Frosted glass that matches macOS dark HUD panels.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// The look shared by every floating panel: frosted midnight glass, soft border, rounded corners.
struct PanelChrome: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffect(material: .hudWindow)
                    Theme.midnight.opacity(0.72)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke.opacity(0.9), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func panelChrome(radius: CGFloat = 14) -> some View { modifier(PanelChrome(radius: radius)) }

    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct WaffleMark: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.accentGradient)
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(Color(hex: "#7A4A12").opacity(0.85))
        }
        .frame(width: size, height: size)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(Color(hex: "#2A1A05"))
            .background(Theme.accentGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(Theme.raised.opacity(configuration.isPressed ? 1 : 0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct ChipButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? Color(hex: "#2A1A05") : Theme.text)
            .background(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.raised.opacity(configuration.isPressed ? 1 : 0.6)), in: Capsule())
    }
}

struct CategoryDot: View {
    var category: IssueCategory
    var size: CGFloat = 8
    var body: some View { Circle().fill(Theme.color(category)).frame(width: size, height: size) }
}

/// Circular overall score, like a progress ring.
struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 64
    var color: Color {
        switch score {
        case 85...: return Theme.success
        case 65..<85: return Theme.syrup
        default: return Theme.danger
        }
    }
    var body: some View {
        ZStack {
            Circle().stroke(Theme.raised, lineWidth: size * 0.1)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.32, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("score").font(.system(size: size * 0.13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: score)
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorBanner: View {
    var message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.syrup)
            Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.syrup.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WorkingView: View {
    var label = "Thinking…"
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Wrapping row of views (chips, tags).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            widest = max(widest, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxWidth, widest), height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Reports a view's size so floating panels can grow and shrink with their content.
struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

extension View {
    func reportSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
            .onPreferenceChange(SizeKey.self, perform: onChange)
    }
}

/// Plain multi-line text box with a placeholder.
struct TextArea: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 90
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder).font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(Theme.midnight, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Copies text to the clipboard.
func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
