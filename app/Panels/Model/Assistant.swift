import Foundation
import Observation
import Security
import UIKit

// MARK: - Key storage

/// The user's own OpenAI key: kept in the Keychain, never in the app bundle.
/// If the Keychain refuses (e.g. a build signed without keychain entitlements), it falls back to a
/// file protected by iOS Data Protection, so a saved key is never silently lost.
enum KeyStore {
    private static let service = "ai.connectly.panels.openai"
    private static let account = "openai-api-key"

    private static var fallbackURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".openai-key")
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var openAIKey: String? {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
                return key
            }
            if let data = try? Data(contentsOf: fallbackURL), let key = String(data: data, encoding: .utf8), !key.isEmpty {
                return key
            }
            return nil
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            try? FileManager.default.removeItem(at: fallbackURL)
            guard let newValue, !newValue.isEmpty else { return }
            var add = baseQuery
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            if status != errSecSuccess {
                print("Keychain save failed (\(status)); using protected file instead")
                try? Data(newValue.utf8).write(to: fallbackURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    static var hasKey: Bool { openAIKey != nil }
}

// MARK: - OpenAI client

struct OpenAIClient {
    enum Failure: LocalizedError {
        case noKey, http(Int, String), network(String)
        var errorDescription: String? {
            switch self {
            case .noKey: "Add your OpenAI API key in Settings to ask questions."
            case .http(401, _): "OpenAI rejected the key. Check it in Settings."
            case .http(429, let m): "OpenAI rate limit or quota reached. \(m)"
            case .http(let code, let m): "OpenAI error \(code). \(m)"
            case .network(let m): "Couldn't reach OpenAI (\(m)). The assistant needs a connection; everything else works offline."
            }
        }
    }

    let key: String
    private let base = URL(string: "https://api.openai.com/v1")!

    /// Chat models available to this key, best defaults first.
    func chatModels() async throws -> [String] {
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        try check(response, data)
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        let ids = try JSONDecoder().decode(List.self, from: data).data.map(\.id)
        let excluded = ["audio", "realtime", "transcribe", "tts", "image", "search", "embedding", "moderation", "instruct", "codex", "computer"]
        let chat = ids.filter { id in
            (id.hasPrefix("gpt-") || id.hasPrefix("o")) && !excluded.contains(where: id.contains) && !id.contains(where: { $0 == ":" })
        }
        return chat.sorted { Self.rank($0) < Self.rank($1) || (Self.rank($0) == Self.rank($1) && $0 > $1) }
    }

    /// Preferred defaults: small, fast, vision-capable models first.
    static let preferred = ["gpt-5-mini", "gpt-5.1-mini", "gpt-4.1-mini", "gpt-4o-mini", "gpt-5", "gpt-4.1", "gpt-4o"]
    private static func rank(_ id: String) -> Int { preferred.firstIndex(of: id) ?? preferred.count }

    /// Streams the reply text as it arrives.
    func stream(model: String, messages: [[String: Any]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": messages])
                    request.timeoutInterval = 120

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch {
                        throw Failure.network(error.localizedDescription)
                    }
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw Failure.http(http.statusCode, Self.message(from: body))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String
                        else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: request) } catch { throw Failure.network(error.localizedDescription) }
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.http(http.statusCode, Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String {
        struct Envelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message ?? ""
    }
}

// MARK: - Conversation

enum AssistantContext: Equatable, Identifiable {
    case library
    case page(Page, showingComic: Bool)
    case term(Term)

    var id: String {
        switch self {
        case .library: "library"
        case .page(let p, let comic): "page:\(p.id):\(comic)"
        case .term(let t): "term:\(t.id)"
        }
    }

    var title: String {
        switch self {
        case .library: "Ask the library"
        case .page(let p, _): p.title
        case .term(let t): t.term
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var image: UIImage?
    var sources: [String] = []
    var failed = false
}

@Observable
final class AssistantSession {
    let context: AssistantContext
    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming = false
    private var task: Task<Void, Never>?

    init(context: AssistantContext) { self.context = context }

    var suggestions: [String] {
        switch context {
        case .library:
            ["What should I read first?", "Explain AI alignment in two minutes", "How do the fellowship projects connect?", "Quiz me on something random"]
        case .page:
            ["Explain this page like I'm 12", "Give me another analogy", "What's the key caveat here?", "Ask me 3 questions about it"]
        case .term:
            ["Give me an everyday example", "How is it different from related terms?", "Where does this show up in practice?"]
        }
    }

    func send(_ text: String, image: UIImage?, store: ContentStore, model: String) {
        guard !isStreaming, let key = KeyStore.openAIKey else {
            if KeyStore.openAIKey == nil {
                messages.append(ChatMessage(role: .assistant, text: OpenAIClient.Failure.noKey.errorDescription!, failed: true))
            }
            return
        }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || image != nil else { return }

        let related = relatedPages(for: question, store: store)
        messages.append(ChatMessage(role: .user, text: question, image: image))
        let reply = ChatMessage(role: .assistant, text: "", sources: sourceIds(related))
        messages.append(reply)
        let replyId = reply.id
        isStreaming = true

        let payload = buildMessages(store: store, related: related)
        task = Task { @MainActor in
            do {
                for try await chunk in OpenAIClient(key: key).stream(model: model, messages: payload) {
                    if let i = messages.firstIndex(where: { $0.id == replyId }) { messages[i].text += chunk }
                }
            } catch is CancellationError {
            } catch {
                if let i = messages.firstIndex(where: { $0.id == replyId }) {
                    messages[i].text = error.localizedDescription
                    messages[i].failed = true
                }
            }
            isStreaming = false
        }
    }

    func stop() {
        task?.cancel()
        isStreaming = false
    }

    // MARK: Prompt

    private func relatedPages(for question: String, store: ContentStore) -> [Page] {
        var current: String?
        if case .page(let p, _) = context { current = p.id }
        return store.search.search(question, limit: 20)
            .filter { $0.kind == .page && $0.itemId != current }
            .prefix(4)
            .compactMap { store.pages[$0.itemId] }
    }

    private func sourceIds(_ related: [Page]) -> [String] {
        var ids: [String] = []
        if case .page(let p, _) = context { ids.append(p.id) }
        return ids + related.map(\.id)
    }

    private func buildMessages(store: ContentStore, related: [Page]) -> [[String: Any]] {
        var result: [[String: Any]] = [["role": "system", "content": systemPrompt(store: store)]]
        let history = messages.dropLast() // the empty reply being streamed
        for (i, message) in history.enumerated() {
            switch message.role {
            case .assistant:
                guard !message.failed else { continue }
                result.append(["role": "assistant", "content": message.text])
            case .user:
                var parts: [[String: Any]] = []
                var text = message.text.isEmpty ? "What is in this image?" : message.text
                // The newest question carries the library excerpts found for it.
                if i == history.count - 1, !related.isEmpty {
                    text += "\n\n---\nPossibly relevant pages from the library (use them if they help, cite their titles):\n" +
                        related.map { pageDigest($0, store: store, limit: 1400) }.joined(separator: "\n\n")
                }
                parts.append(["type": "text", "text": text])
                if let image = message.image, let url = Self.dataURL(image) {
                    parts.append(["type": "image_url", "image_url": ["url": url]])
                }
                // Asked from the comic view: the page image rides along with the first question of the chat.
                if i == 0, case .page(let page, true) = context,
                   let comic = UIImage(contentsOfFile: store.url(page.image).path), let url = Self.dataURL(comic) {
                    parts.append(["type": "image_url", "image_url": ["url": url]])
                }
                result.append(["role": "user", "content": parts])
            }
        }
        return result
    }

    private func systemPrompt(store: ContentStore) -> String {
        let library = store.collections.map { c in
            "- \(c.title): " + c.books.map(\.title).joined(separator: "; ")
        }.joined(separator: "\n")
        var prompt = """
        You are the study companion inside Panels, an offline app of illustrated comic study guides. \
        The reader is a curious learner, often reading on a train or at the gym on a phone.

        How to answer:
        - Plain, friendly language; short paragraphs; use an everyday analogy when it helps. Define jargon in the same sentence.
        - Keep answers phone-sized (usually under 180 words) unless asked for more. Light Markdown only (bold, italics, short lists).
        - Stay accurate. Say when something is uncertain or beyond the material. Never invent results, numbers or citations.
        - Fellowship books describe PROPOSED research: never present their experiments as completed. Probes and monitors are imperfect measurements, not mind readers; don't attribute feelings or intentions to models.
        - When you rely on a page, mention its title in bold so the reader can find it.
        - If asked to quiz, ask one question at a time and wait for the answer.

        The library:
        \(library)
        """
        switch context {
        case .library:
            prompt += "\n\nThe reader is on the home screen; help them choose what to learn and answer questions about anything in the library."
        case .page(let page, let showingComic):
            let book = store.book(for: page)
            prompt += "\n\nThe reader is on page \(page.number) of \(book?.pages.count ?? 0) of the book “\(book?.title ?? "")”."
            if let objectives = book?.objectives, !objectives.isEmpty {
                prompt += " The book's goals: " + objectives.joined(separator: " ")
            }
            prompt += "\n\nCurrent page:\n" + pageDigest(page, store: store, limit: 4000)
            if showingComic { prompt += "\n\nThey are looking at the comic version; its image is attached to their first message." }
        case .term(let term):
            prompt += "\n\nThe reader is looking at the glossary entry “\(term.term)”\(term.aka.isEmpty ? "" : " (also: \(term.aka.joined(separator: ", ")))"): \(term.definition)"
        }
        return prompt
    }

    private func pageDigest(_ page: Page, store: ContentStore, limit: Int) -> String {
        var lines = ["# \(page.title)" + (store.book(for: page).map { " (from “\($0.title)”)" } ?? "")]
        if !page.subtitle.isEmpty { lines.append(page.subtitle) }
        if !page.wordKey.isEmpty { lines.append("Word key: \(page.wordKey)") }
        for panel in page.panels {
            lines.append("\(panel.number). \(panel.heading): \(panel.body)" + (panel.code.map { "\n\($0)" } ?? ""))
        }
        if !page.footer.isEmpty { lines.append("Takeaway: \(page.footer)") }
        let text = lines.joined(separator: "\n")
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// JPEG data URL, downscaled so a comic page stays small but readable.
    static func dataURL(_ image: UIImage, maxSide: CGFloat = 1280) -> String? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.75) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }
}
