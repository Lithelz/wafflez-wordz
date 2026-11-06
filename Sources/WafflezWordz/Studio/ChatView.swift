import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WafflezCore

struct ChatAttachment: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var block: JSONValue
}

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    var role: String
    var text: String
    var attachments: [String] = []
    var contextLabel: String?
}

/// One AI chat conversation. The history sent to Claude is append-only so earlier turns stay valid.
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var streaming = false
    @Published var error: String?
    @Published var pending: [ChatAttachment] = []
    private var history: [JSONValue] = []
    private var lastContext: String?
    private let system: String
    private let state = AppState.shared
    private var task: Task<Void, Never>?

    init() {
        system = WafflezAI.chatSystem(dialect: AppState.shared.settings.dialect)
    }

    static let maxFiles = 5
    static let maxImageBytes = 7 * 1024 * 1024
    static let maxFileBytes = 30 * 1024 * 1024

    func reset() {
        task?.cancel()
        messages = []
        history = []
        lastContext = nil
        pending = []
        error = nil
        streaming = false
    }

    func stop() { task?.cancel() }

    /// Sends a message. `context` is text from the screen or document, included when it changes.
    func send(_ text: String, context: String?, contextLabel: String?) {
        let question = text.trimmed
        guard !question.isEmpty || !pending.isEmpty, !streaming else { return }
        error = nil
        var blocks: [JSONValue] = []
        var label: String?
        if let context, !context.trimmed.isEmpty, context != lastContext {
            blocks.append(["type": "text", "text": .string("<context source=\"\(contextLabel ?? "screen")\">\n\(String(context.prefix(40000)))\n</context>")])
            lastContext = context
            label = contextLabel
        }
        blocks += pending.map(\.block)
        blocks.append(["type": "text", "text": .string(question.isEmpty ? "Please look at the attached files." : question)])
        messages.append(ChatMessage(role: "user", text: question, attachments: pending.map(\.name), contextLabel: label))
        pending = []
        let userTurn: JSONValue = ["role": "user", "content": .array(blocks)]

        let ai: WafflezAI
        do { ai = try state.ai() } catch {
            self.error = error.localizedDescription
            return
        }
        history.append(userTurn)
        messages.append(ChatMessage(role: "assistant", text: ""))
        streaming = true
        let index = messages.count - 1
        let sys = system
        let convo = history
        task = Task { @MainActor in
            do {
                let response = try await ai.client.stream(system: sys, messages: convo, maxTokens: 32000, effort: .medium) { [weak self] delta in
                    Task { @MainActor in
                        guard let self, index < self.messages.count else { return }
                        self.messages[index].text += delta
                    }
                }
                // Keep the assistant turn exactly as returned (including thinking blocks) for the next request.
                self.history.append(["role": "assistant", "content": .array(response.content)])
                if index < self.messages.count, self.messages[index].text.isEmpty { self.messages[index].text = response.text }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
                self.history.removeLast()
                if index < self.messages.count, self.messages[index].text.isEmpty { self.messages.remove(at: index) }
            }
            self.streaming = false
        }
    }

    // MARK: Files

    func attach(urls: [URL]) {
        for url in urls {
            guard pending.count < Self.maxFiles else { error = "You can attach up to \(Self.maxFiles) files per message."; return }
            do { pending.append(try Self.block(for: url)) } catch { self.error = error.localizedDescription }
        }
    }

    func attach(image: NSImage, name: String = "Pasted image") {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        guard png.count <= Self.maxImageBytes else { error = "Images can be up to 7 MB."; return }
        pending.append(ChatAttachment(name: name, block: ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": .string(png.base64EncodedString())]]))
    }

    struct FileError: LocalizedError { var errorDescription: String? }

    static func block(for url: URL) throws -> ChatAttachment {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let images = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
        if let media = images[ext] {
            guard size <= maxImageBytes else { throw FileError(errorDescription: "\(name) is larger than 7 MB.") }
            let data = try Data(contentsOf: url)
            return ChatAttachment(name: name, block: ["type": "image", "source": ["type": "base64", "media_type": .string(media), "data": .string(data.base64EncodedString())]])
        }
        guard size <= maxFileBytes else { throw FileError(errorDescription: "\(name) is larger than 30 MB.") }
        if ext == "pdf" {
            let data = try Data(contentsOf: url)
            return ChatAttachment(name: name, block: ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": .string(data.base64EncodedString())], "title": .string(name)])
        }
        var text: String?
        if ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive"].contains(ext) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        } else if ["pages", "key", "numbers", "xlsx", "xls", "pptx", "gdoc", "gsheet", "gslides"].contains(ext) {
            throw FileError(errorDescription: "\(name): export it as PDF (or CSV for spreadsheets) and attach that. Google Docs, Sheets and Slides can be downloaded as PDF from File → Download.")
        } else {
            text = try? String(contentsOf: url, encoding: .utf8)
        }
        guard let text, !text.isEmpty else { throw FileError(errorDescription: "Couldn't read \(name).") }
        return ChatAttachment(name: name, block: ["type": "text", "text": .string("<document name=\"\(name)\">\n\(String(text.prefix(200_000)))\n</document>")])
    }
}

struct ChatView: View {
    @ObservedObject var session: ChatSession
    /// Returns (context text, label) for the current screen or document.
    var contextProvider: (() -> (String, String))?
    var attachTargets: (() -> [(String, () -> String)])? = nil
    var insertAction: ((String) -> Void)? = nil
    var compact = false

    @State private var draft = ""
    @State private var includeContext = true
    @State private var attachedWindow: (String, () -> String)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty { emptyState }
                        ForEach(session.messages) { m in bubble(m).id(m.id) }
                        if let error = session.error { ErrorBanner(message: error) }
                    }
                    .padding(compact ? 12 : 18)
                }
                .onChange(of: session.messages.last?.text) { _, _ in
                    if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider().overlay(Theme.stroke)
            composer
        }
        .background(Theme.midnight)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { WaffleMark(size: 26); Text("Chat with Wafflez").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text) }
            Text("Ask anything about what you're writing or what's on your screen. Attach up to 5 files: PDFs, Word docs, text, code or images.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                ForEach(["Summarize this", "Give me feedback on my draft", "Write a reply", "Make this more concise", "What's the main argument?"], id: \.self) { p in
                    Button(p) { draft = p; focused = true }.buttonStyle(ChipButtonStyle())
                }
            }
        }
        .card()
    }

    private func bubble(_ m: ChatMessage) -> some View {
        VStack(alignment: m.role == "user" ? .trailing : .leading, spacing: 4) {
            if let label = m.contextLabel {
                Label("Using \(label)", systemImage: "rectangle.on.rectangle").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
            }
            if !m.attachments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(m.attachments, id: \.self) { a in
                        Label(a, systemImage: "paperclip").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.raised, in: Capsule())
                    }
                }
            }
            if m.role == "assistant" && m.text.isEmpty {
                WorkingView(label: "Thinking…")
            } else {
                Text(LocalizedStringKey(m.text))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(m.role == "user" ? Theme.indigo.opacity(0.25) : Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: compact ? 320 : 560, alignment: m.role == "user" ? .trailing : .leading)
            }
            if m.role == "assistant" && !m.text.isEmpty && !(session.streaming && m.id == session.messages.last?.id) {
                HStack(spacing: 6) {
                    Button { copyToClipboard(m.text) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(GhostButtonStyle(tint: Theme.textSecondary))
                    if let insertAction {
                        Button { insertAction(m.text) } label: { Label("Insert", systemImage: "text.insert") }.buttonStyle(GhostButtonStyle(tint: Theme.syrup))
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.role == "user" ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.pending) { a in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                Text(a.name).lineLimit(1)
                                Button { session.pending.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                            }
                            .font(.system(size: 11)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.raised, in: Capsule())
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Add photos and files…") { pickFiles() }
                    Button("Paste image from clipboard") {
                        if let img = NSImage(pasteboard: .general) { session.attach(image: img) }
                    }
                    if let attachTargets {
                        Divider()
                        Menu("Attach a window") {
                            ForEach(Array(attachTargets().enumerated()), id: \.offset) { _, target in
                                Button(target.0) { attachedWindow = target; includeContext = true }
                            }
                        }
                    }
                    Divider()
                    Button("New chat") { session.reset() }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                TextField("Message Wafflez…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(send)

                if session.streaming {
                    Button { session.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 20)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.danger)
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(draft.trimmed.isEmpty && session.pending.isEmpty ? Theme.textTertiary : Theme.syrup)
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in session.attach(urls: [url]) } }
                    }
                }
                return true
            }

            if contextProvider != nil || attachedWindow != nil {
                HStack(spacing: 6) {
                    Toggle(isOn: $includeContext) {
                        Text(attachedWindow.map { "Use \"\($0.0)\"" } ?? "Use what's in front of me")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                    .toggleStyle(.checkbox)
                    if attachedWindow != nil {
                        Button("Reset") { attachedWindow = nil }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.syrup)
                    }
                    Spacer()
                }
            }
        }
        .padding(compact ? 10 : 14)
    }

    private func send() {
        var ctx: String?
        var label: String?
        if includeContext {
            if let attachedWindow {
                ctx = attachedWindow.1()
                label = attachedWindow.0
            } else if let contextProvider {
                let (c, l) = contextProvider()
                ctx = c
                label = l
            }
        }
        session.send(draft, context: ctx, contextLabel: label)
        draft = ""
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .plainText, .rtf, .html, .sourceCode, .commaSeparatedText, .json,
                                     UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText, .data]
        if panel.runModal() == .OK { session.attach(urls: panel.urls) }
    }
}
