import PhotosUI
import SwiftUI

struct AssistantView: View {
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("openaiModel") private var model = ""

    @State private var session: AssistantSession
    @State private var draft = ""
    @State private var attachment: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var hasKey = KeyStore.openAIKey != nil
    @FocusState private var focused: Bool

    private let onOpenPage: ((Page) -> Void)?
    /// Sent automatically when the chat opens (e.g. "Explain it simpler").
    private let initialPrompt: String?
    @State private var sentInitial = false

    init(context: AssistantContext, initialPrompt: String? = nil, onOpenPage: ((Page) -> Void)? = nil) {
        _session = State(initialValue: AssistantSession(context: context))
        self.initialPrompt = initialPrompt
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasKey {
                    conversation
                    inputBar
                } else {
                    ScrollView {
                        KeySetupCard { hasKey = true }
                            .padding(20)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            hasKey = KeyStore.hasKey
            sendInitialIfReady()
        }
        .onChange(of: hasKey) { _, _ in sendInitialIfReady() }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    attachment = image
                }
                photoItem = nil
            }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contextCard
                    if session.messages.isEmpty {
                        suggestions
                    }
                    ForEach(session.messages) { message in
                        MessageBubble(message: message, isStreaming: session.isStreaming && message.id == session.messages.last?.id, openSource: open)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var contextCard: some View {
        HStack(spacing: 12) {
            switch session.context {
            case .page(let page, let comic):
                ContentImage(path: page.thumb)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title).font(.serif(.headline)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(comic ? "Knows this page (text and comic image) and the whole library" : "Knows this page and the whole library")
                        .font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                }
            case .term(let term):
                Image(systemName: "character.book.closed.fill").font(.title2).foregroundStyle(Theme.categoryTint(term.category))
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.term).font(.serif(.headline)).foregroundStyle(Theme.ink)
                    Text("Knows this word and the whole library").font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                }
            case .library:
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your study companion").font(.serif(.headline)).foregroundStyle(Theme.ink)
                    Text("Ask about anything in the \(store.pageCount) pages, or send a photo").font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(radius: 16)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.suggestions, id: \.self) { s in
                Button { send(s) } label: {
                    HStack {
                        Text(s).font(.serif(.subheadline)).foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: "arrow.up.circle").foregroundStyle(Theme.accent.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment {
                HStack {
                    Image(uiImage: attachment)
                        .resizable().scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { self.attachment = nil } label: {
                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                        }
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("Attach a photo")

                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .font(.serif(.body))
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
                    .onSubmit { send(draft) }

                Button {
                    session.isStreaming ? session.stop() : send(draft)
                } label: {
                    Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.onTint)
                        .frame(width: 38, height: 38)
                        .background(Theme.accent, in: Circle())
                }
                .disabled(!session.isStreaming && draft.trimmingCharacters(in: .whitespaces).isEmpty && attachment == nil)
                .accessibilityLabel(session.isStreaming ? "Stop" : "Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Actions

    private func sendInitialIfReady() {
        guard hasKey, !sentInitial, let initialPrompt else { return }
        sentInitial = true
        send(initialPrompt)
    }

    private func send(_ text: String) {
        let image = attachment
        draft = ""
        attachment = nil
        Task {
            if model.isEmpty, let key = KeyStore.openAIKey {
                model = (try? await OpenAIClient(key: key).chatModels().first) ?? OpenAIClient.preferred[0]
            }
            session.send(text, image: image, store: store, model: model)
        }
    }

    private func open(_ page: Page) {
        if let onOpenPage {
            dismiss()
            onOpenPage(page)
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.read(page: page, in: store) }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    let openSource: (Page) -> Void
    @Environment(ContentStore.self) private var store

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 8) {
                    if let image = message.image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.serif(.body))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if message.text.isEmpty && isStreaming {
                    TypingDots()
                } else {
                    Text(markdown(message.text))
                        .font(.serif(.body))
                        .foregroundStyle(message.failed ? Theme.tint("coral") : Theme.ink.opacity(0.9))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let pages = message.sources.compactMap { store.pages[$0] }
                if !pages.isEmpty && !isStreaming && !message.failed {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(pages) { page in
                                Button { openSource(page) } label: {
                                    Label(page.title, systemImage: "book")
                                        .font(.rounded(.caption, weight: .semibold))
                                        .foregroundStyle(Theme.inkSecondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Theme.sunken, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 18)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct TypingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.inkTertiary)
                    .frame(width: 7, height: 7)
                    .opacity(0.35 + 0.65 * max(0, sin(phase + Double(i) * 0.9)))
            }
        }
        .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { phase = .pi * 2 } }
        .accessibilityLabel("Thinking")
    }
}

/// Paste-your-own-key setup, shown in the chat and in Settings.
struct KeySetupCard: View {
    var onSaved: () -> Void = {}
    @AppStorage("openaiModel") private var model = ""
    @State private var key = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "key.horizontal.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text("Connect your OpenAI key")
                .font(.serif(.title2, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("The assistant uses your own OpenAI account. Your key is stored in this iPhone's Keychain and only sent to OpenAI. Questions, page text and images you ask about go to OpenAI; everything else stays offline.")
                .font(.serif(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("sk-…", text: $key)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if checking { ProgressView().tint(Theme.onTint) }
                    Text(checking ? "Checking…" : "Save and check").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(FilledButtonStyle(tint: Theme.accent))
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            if let status {
                Text(status).font(.rounded(.footnote)).foregroundStyle(Theme.inkSecondary)
            }
            Link("Get a key at platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.rounded(.footnote, weight: .semibold))
        }
        .padding(20)
        .card(radius: 22)
    }

    private func save() async {
        checking = true
        defer { checking = false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the key even if the check below fails (offline, flaky network…); only a rejected key is removed.
        KeyStore.openAIKey = trimmed
        do {
            let models = try await OpenAIClient(key: trimmed).chatModels()
            if model.isEmpty || !models.contains(model) { model = models.first ?? OpenAIClient.preferred[0] }
            status = "Connected. Using \(model)."
            onSaved()
        } catch OpenAIClient.Failure.http(401, _) {
            KeyStore.openAIKey = nil
            status = OpenAIClient.Failure.http(401, "").localizedDescription
        } catch {
            status = "Saved. Couldn't verify it right now: \(error.localizedDescription)"
            onSaved()
        }
    }
}

/// Settings section: key status and model choice.
struct AssistantSettingsSection: View {
    @AppStorage("openaiModel") private var model = ""
    @State private var hasKey = KeyStore.openAIKey != nil
    @State private var models: [String] = []
    @State private var error: String?

    var body: some View {
        Section {
            if hasKey {
                LabeledContent("API key", value: "Saved in Keychain")
                Picker("Model", selection: $model) {
                    ForEach(models.isEmpty ? [model].filter { !$0.isEmpty } : models, id: \.self) { Text($0).tag($0) }
                }
                .task { await loadModels() }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Button("Remove key", role: .destructive) {
                    KeyStore.openAIKey = nil
                    hasKey = false
                }
            } else {
                KeySetupCard { hasKey = true }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("Assistant")
        } footer: {
            Text("Uses your own OpenAI account; requests go straight from this phone to OpenAI.")
        }
    }

    private func loadModels() async {
        guard let key = KeyStore.openAIKey else { return }
        do {
            models = try await OpenAIClient(key: key).chatModels()
            if model.isEmpty || !models.contains(model) { model = models.first ?? model }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
