import SwiftUI
import WafflezCore

/// What a suggestion card can do. The same card is used in other apps and in the Studio editor.
struct CardActions {
    var accept: (String) -> Void
    var dismiss: () -> Void
    var addToDictionary: (String) -> Void
    var turnOffRule: (String) -> Void
    var report: (String) -> Void
    var reviewAll: (() -> Void)?
    var aiRewrite: ((Suggestion) async throws -> String)?
}

struct SuggestionCardView: View {
    let suggestion: Suggestion
    let actions: CardActions
    var position: (index: Int, total: Int)? = nil
    var onNext: (() -> Void)? = nil

    @State private var showLearnMore = false
    @State private var aiText: String?
    @State private var aiWorking = false
    @State private var aiError: String?
    @State private var reported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !suggestion.replacements.isEmpty {
                replacements
            } else if suggestion.original.count < 140 {
                Text(suggestion.original)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.color(suggestion.category)).frame(height: 2).offset(y: 2) }
            }
            Text(suggestion.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if suggestion.offersAIRewrite, let ai = actions.aiRewrite {
                aiSection(ai)
            }

            if showLearnMore, let more = suggestion.learnMore {
                Text(more)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .panelChrome()
    }

    private var header: some View {
        HStack(spacing: 8) {
            CategoryDot(category: suggestion.category)
            Text(suggestion.category.displayName.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.color(suggestion.category))
            Text("·").foregroundStyle(Theme.textTertiary)
            Text(suggestion.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let position, position.total > 1 {
                Text("\(position.index + 1)/\(position.total)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            moreMenu
        }
    }

    private var replacements: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestion.original.trimmed.isEmpty && suggestion.original.count < 120 {
                Text(suggestion.original)
                    .font(.system(size: 13))
                    .strikethrough(true, color: Theme.danger.opacity(0.8))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(3)
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(suggestion.replacements.prefix(4).enumerated()), id: \.offset) { i, rep in
                    Button { actions.accept(rep) } label: {
                        Text(rep.isEmpty ? "Remove" : rep.replacingOccurrences(of: "\n", with: "⏎"))
                            .font(.system(size: 13.5, weight: i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? Color(hex: "#0B1020") : Theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(i == 0 ? AnyShapeStyle(Theme.color(suggestion.category)) : AnyShapeStyle(Theme.raised), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help("Accept this suggestion")
                }
            }
        }
    }

    @ViewBuilder
    private func aiSection(_ ai: @escaping (Suggestion) async throws -> String) -> some View {
        if let aiText {
            VStack(alignment: .leading, spacing: 8) {
                Text(aiText).font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Accept rewrite") { actions.accept(aiText) }.buttonStyle(PrimaryButtonStyle())
                    Button("Retry") { run(ai) }.buttonStyle(GhostButtonStyle())
                }
            }
            .padding(10)
            .background(Theme.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        } else if aiWorking {
            WorkingView(label: "Rewriting…")
        } else {
            Button { run(ai) } label: { Label("Rewrite with AI", systemImage: "sparkles") }
                .buttonStyle(GhostButtonStyle(tint: Theme.indigo))
        }
        if let aiError { ErrorBanner(message: aiError) }
    }

    private func run(_ ai: @escaping (Suggestion) async throws -> String) {
        aiWorking = true
        aiError = nil
        aiText = nil
        Task { @MainActor in
            do { aiText = try await ai(suggestion) } catch { aiError = error.localizedDescription }
            aiWorking = false
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { actions.dismiss() } label: { Label("Dismiss", systemImage: "trash") }
                .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
            if suggestion.isSpelling {
                Button { actions.addToDictionary(suggestion.original) } label: { Label("Add to dictionary", systemImage: "book") }
                    .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
            }
            Spacer()
            if let onNext, let position, position.total > 1 {
                Button { onNext() } label: { Image(systemName: "chevron.right") }.buttonStyle(GhostButtonStyle())
                    .help("Next suggestion")
            }
            if let reviewAll = actions.reviewAll {
                Button("Review all") { reviewAll() }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var moreMenu: some View {
        Menu {
            if suggestion.learnMore != nil {
                Button(showLearnMore ? "Hide explanation" : "Learn more") { showLearnMore.toggle() }
            }
            Button("Turn off suggestions like this") { actions.turnOffRule(suggestion.ruleID) }
            Button(reported ? "Reported — thanks!" : "Report a wrong suggestion") {
                reported = true
                actions.report("User reported this suggestion as wrong")
            }
            .disabled(reported)
            Divider()
            Button("Copy suggestion") { copyToClipboard(suggestion.replacements.first ?? suggestion.original) }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Small toast with Undo after accepting a suggestion.
struct UndoToastView: View {
    var message: String
    var onUndo: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(1)
            Button("Undo", action: onUndo).buttonStyle(GhostButtonStyle(tint: Theme.syrup))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .panelChrome(radius: 20)
    }
}
