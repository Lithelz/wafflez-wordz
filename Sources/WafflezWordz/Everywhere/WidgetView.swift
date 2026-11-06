import SwiftUI
import WafflezCore

/// The floating bubble beside the text you're writing: suggestion count, tone emoji and the AI lightbulb.
struct WidgetView: View {
    var count: Int
    var topCategory: IssueCategory?
    var toneEmoji: String?
    var checking: Bool
    var showReply: Bool
    var onOpen: () -> Void
    var onCompose: () -> Void
    var onTone: () -> Void
    var onReply: () -> Void
    var onDragEnded: (CGSize) -> Void

    @State private var drag: CGSize = .zero

    var body: some View {
        HStack(spacing: 4) {
            if showReply {
                Button(action: onReply) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).frame(height: 26)
                        .foregroundStyle(Theme.text)
                        .background(Theme.surface.opacity(0.95), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Reply quickly with AI")
            }
            Button(action: onCompose) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 24, height: 24)
                    .background(Theme.surface.opacity(0.95), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Write with AI")

            if let toneEmoji {
                Button(action: onTone) {
                    Text(toneEmoji).font(.system(size: 13))
                        .frame(width: 24, height: 24)
                        .background(Theme.surface.opacity(0.95), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("How your writing may sound")
            }

            Button(action: onOpen) {
                ZStack {
                    Circle().fill(count == 0 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.color(topCategory ?? .correctness)))
                    if checking {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else if count == 0 {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: "#2A1A05"))
                    } else {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: count > 9 ? 10 : 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "#0B1020"))
                    }
                }
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .help(count == 0 ? "Looking good" : "\(count) suggestion\(count == 1 ? "" : "s")")
        }
        .padding(2)
        .offset(drag)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag = $0.translation }
                .onEnded { v in
                    drag = .zero
                    onDragEnded(v.translation)
                }
        )
    }
}

/// The blue bar shown at the start of selected text. Click it to rewrite with AI.
struct SelectionPillView: View {
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.indigo).frame(width: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Theme.indigo, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 3)
            }
            .frame(height: 22)
        }
        .buttonStyle(.plain)
        .help("Rewrite with AI")
    }
}

/// Tone breakdown card.
struct ToneCardView: View {
    var tone: ToneResult
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How your text may sound").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            ToneDetailView(tone: tone)
        }
        .padding(14)
        .frame(width: 290)
        .panelChrome()
    }
}

struct ToneDetailView: View {
    var tone: ToneResult
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(tone.tones) { t in
                HStack(spacing: 8) {
                    Text(t.emoji).font(.system(size: 18))
                    Text(t.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Capsule().fill(Theme.raised).frame(width: 80, height: 6)
                        .overlay(alignment: .leading) { Capsule().fill(Theme.syrup).frame(width: 80 * max(0.08, t.strength), height: 6) }
                }
            }
            Divider().overlay(Theme.stroke)
            meter("Formality", tone.formality, "Casual", "Formal")
            meter("Confidence", tone.confidence, "Unsure", "Confident")
            meter("Warmth", tone.friendliness, "Cool", "Warm")
            Text("A prediction of how a reader may hear you, based on word choice and punctuation.")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func meter(_ title: String, _ value: Double, _ low: String, _ high: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Circle().fill(Theme.indigo).frame(width: 10, height: 10).offset(x: (g.size.width - 10) * value)
                }
            }
            .frame(height: 10)
            HStack { Text(low); Spacer(); Text(high) }.font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
    }
}
