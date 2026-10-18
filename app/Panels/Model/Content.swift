import Foundation

// Mirrors app/Panels/Content/content.json written by app/tools/build_content.py.

struct ContentFile: Decodable {
    let version: Int
    let collections: [Collection]
    let glossary: [Term]
    /// Everyday word -> technical phrases, for search query expansion.
    let synonyms: [String: [String]]?
    let quiz: [Question]?
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

    var hasText: Bool { !panels.isEmpty }

    static func == (a: Page, b: Page) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
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
