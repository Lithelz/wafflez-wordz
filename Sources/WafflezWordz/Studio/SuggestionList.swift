import SwiftUI
import WafflezCore

/// One compact row per suggestion, with quick Accept and Dismiss.
struct SuggestionRow: View {
    var suggestion: Suggestion
    var onSelect: () -> Void
    var onAccept: (() -> Void)?
    var onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.color(suggestion.category)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.color(suggestion.category))
                HStack(spacing: 6) {
                    Text(suggestion.original.trimmed.isEmpty ? "␣" : suggestion.original)
                        .font(.system(size: 13))
                        .foregroundStyle(suggestion.replacements.isEmpty ? Theme.text : Theme.textTertiary)
                        .strikethrough(!suggestion.replacements.isEmpty, color: Theme.danger.opacity(0.7))
                        .lineLimit(2)
                    if let rep = suggestion.replacements.first {
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        Text(rep.isEmpty ? "Remove" : rep).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 4)
            if hovering || onAccept != nil {
                HStack(spacing: 4) {
                    if let onAccept, !suggestion.replacements.isEmpty {
                        Button(action: onAccept) { Image(systemName: "checkmark") }
                            .buttonStyle(GhostButtonStyle(tint: Theme.success)).help("Accept")
                    }
                    Button(action: onDismiss) { Image(systemName: "trash") }
                        .buttonStyle(GhostButtonStyle(tint: Theme.textSecondary)).help("Dismiss")
                }
                .opacity(hovering ? 1 : 0.55)
            }
        }
        .padding(10)
        .background(hovering ? Theme.raised : Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}

/// Category filter chips with counts.
struct CategoryFilterBar: View {
    var counts: [IssueCategory: Int]
    @Binding var filter: IssueCategory?
    var body: some View {
        FlowLayout(spacing: 6) {
            Button { filter = nil } label: { Text("All \(counts.values.reduce(0, +))") }
                .buttonStyle(ChipButtonStyle(selected: filter == nil))
            ForEach(IssueCategory.allCases) { c in
                if let n = counts[c], n > 0 {
                    Button { filter = (filter == c ? nil : c) } label: {
                        HStack(spacing: 5) { CategoryDot(category: c, size: 7); Text("\(c.displayName) \(n)") }
                    }
                    .buttonStyle(ChipButtonStyle(selected: filter == c))
                }
            }
        }
    }
}

/// Suggestions list for an editor (Studio and Quick Check).
struct EditorSuggestionList: View {
    @ObservedObject var controller: EditorController

    var body: some View {
        let all = controller.allSuggestions
        let counts = Dictionary(grouping: all, by: \.category).mapValues(\.count)
        VStack(alignment: .leading, spacing: 10) {
            CategoryFilterBar(counts: counts, filter: $controller.filter)
            if all.contains(where: { !$0.replacements.isEmpty }) {
                Button { controller.acceptAll(in: controller.filter) } label: {
                    Label(controller.filter == nil ? "Accept all fixes" : "Accept all \(controller.filter!.displayName.lowercased()) fixes", systemImage: "checkmark.circle")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.success))
            }
            if controller.suggestions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.syrup)
                    Text(all.isEmpty ? "Looking good! No suggestions right now." : "Nothing in this category.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            ForEach(controller.suggestions) { s in
                SuggestionRow(
                    suggestion: s,
                    onSelect: { controller.reveal(s) },
                    onAccept: s.replacements.isEmpty ? nil : { controller.apply(s, replacement: s.replacements[0]) },
                    onDismiss: { controller.dismiss(s) })
            }
        }
    }
}
