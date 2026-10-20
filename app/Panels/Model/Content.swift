import Foundation

// Mirrors app/Panels/Content/content.json written by app/tools/build_content.py.

struct ContentFile: Decodable {
    let version: Int
    let collections: [Collection]
    let glossary: [Term]
    /// Everyday word -> technical phrases, for search query expansion.
    let synonyms: [String: [String]]?
    let quiz: [Question]?
    let playbook: Playbook?
}

// MARK: - Safety playbook

struct Playbook: Decodable {
    /// The generic research recipe every experiment map follows.
    let recipe: [String]
    let tools: [Tool]
    let experiments: [Experiment]
}

struct Tool: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let what: String
    let useWhen: String
    let limit: String
    let terms: [String]

    enum CodingKeys: String, CodingKey { case id, name, category, what, useWhen, limit = "catch", terms }
}

struct Experiment: Decodable, Identifiable, Hashable {
    let id: String
    let theme: String
    let question: String
    let chain: String
    let tree: [TreeNode]
    let confound: String
    let success: String
    let example: String
    let fellowship: String?
}

struct TreeNode: Decodable, Hashable {
    let step: String
    let how: String?
    let tool: String?
    let outcome: String?
    let branches: [Branch]?
}

struct Branch: Decodable, Hashable {
    let condition: String
    let then: [TreeNode]

    enum CodingKeys: String, CodingKey { case condition = "if", then }
}

struct Collection: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let symbol: String
    let tint: String
    let pageCount: Int
    let books: [Book]

    static func == (a: Collection, b: Collection) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Book: Decodable, Identifiable, Hashable {
    let id: String
    let collectionId: String
    let title: String
    let subtitle: String
    let objectives: [String]
    let cover: String
    let coverImage: String
    let hasVideo: Bool
    let pages: [Page]

    var videoPages: [Page] { pages.filter { $0.video != nil } }
    var totalDuration: Double { pages.compactMap(\.duration).reduce(0, +) }

    static func == (a: Book, b: Book) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Page: Decodable, Identifiable, Hashable {
    let id: String
    let bookId: String
    let number: Int
    let title: String
    let printedTitle: String?
    let subtitle: String
    let panels: [Panel]
    let footer: String
    let wordKey: String
    let summary: String
    let keywords: [String]
    let image: String
    let thumb: String
    let video: String?
    let poster: String?
    let duration: Double?
    /// Pre-recorded Listen mode clips (opening, one per panel, takeaway), when recorded.
    let narration: [NarrationClip]?
    /// Advanced mode: a deeper note per panel (same order as `panels`) and a closing note for the page.
    let deeper: Deeper?
    /// Original readings the page distills (AI Futurism), shown as links under the text.
    let sources: [Source]?

    var hasText: Bool { !panels.isEmpty }

    static func == (a: Page, b: Page) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Source: Decodable, Hashable {
    let title: String
    let url: String
}

struct Deeper: Decodable, Hashable {
    let panels: [String]
    let further: String?
}

struct NarrationClip: Decodable, Hashable {
    let panel: Int?
    let audio: String
    let duration: Double
}

struct Panel: Decodable, Hashable {
    let number: Int
    let heading: String
    let body: String
    let code: String?
}

struct Term: Decodable, Identifiable, Hashable {
    let id: String
    let term: String
    let aka: [String]
    let category: String
    let short: String
    let definition: String
    /// Advanced mode: the expert-level explanation.
    let advanced: String?
    let related: [String]
    let pages: [String]

    var sortLetter: String {
        let first = term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first ?? "#"
        return first.isLetter ? String(first).uppercased() : "#"
    }

    static func == (a: Term, b: Term) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum ReaderMode: String, CaseIterable, Identifiable {
    case comic, text, video
    var id: String { rawValue }

    var label: String {
        switch self {
        case .comic: "Comic"
        case .text: "Text"
        case .video: "Video"
        }
    }

    var symbol: String {
        switch self {
        case .comic: "photo.on.rectangle.angled"
        case .text: "text.alignleft"
        case .video: "play.rectangle"
        }
    }
}
