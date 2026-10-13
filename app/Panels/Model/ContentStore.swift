import Foundation
import Observation

/// Read-only library loaded from the bundled Content folder.
@Observable
final class ContentStore {
    let collections: [Collection]
    let glossary: [Term]
    let synonyms: [String: [String]]
    let quiz: [Question]
    let contentURL: URL

    private(set) var books: [String: Book] = [:]
    private(set) var pages: [String: Page] = [:]
    private(set) var terms: [String: Term] = [:]
    private(set) var collectionsById: [String: Collection] = [:]

    @ObservationIgnored lazy var termMatcher = TermMatcher(terms: glossary)
    @ObservationIgnored lazy var search = SearchEngine(store: self)

    convenience init() {
        guard let url = Bundle.main.url(forResource: "Content", withExtension: nil) else {
            fatalError("Content bundle missing: run app/tools/build_content.py before building")
        }
        self.init(contentURL: url)
    }

    init(contentURL url: URL) {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("content.json")) else {
            fatalError("content.json missing in \(url.path): run app/tools/build_content.py")
        }
        let file: ContentFile
        do {
            file = try JSONDecoder().decode(ContentFile.self, from: data)
        } catch {
            fatalError("content.json does not match the app's model: \(error)")
        }
        contentURL = url
        collections = file.collections
        synonyms = file.synonyms ?? [:]
        quiz = file.quiz ?? []
        glossary = file.glossary.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        for collection in collections {
            collectionsById[collection.id] = collection
            for book in collection.books {
                books[book.id] = book
                for page in book.pages { pages[page.id] = page }
            }
        }
        for term in glossary { terms[term.id] = term }
    }

    func url(_ relative: String) -> URL { contentURL.appendingPathComponent(relative) }

    func book(for page: Page) -> Book? { books[page.bookId] }
    func collection(for book: Book) -> Collection? { collectionsById[book.collectionId] }

    /// Glossary terms not worth highlighting in this book: Git words ("push", "merge") and data-structure
    /// words ("trie", "stack") read as plain English outside their own collections.
    func termsToSkip(in book: Book) -> Set<String> {
        let scoped: [String: Set<String>] = ["Git": ["swe"], "Algorithms": ["leetcode", "ml"], "Data Structures": ["leetcode", "ml"]]
        return Set(glossary.filter { term in
            scoped[term.category].map { !$0.contains(book.collectionId) } ?? false
        }.map(\.id))
    }

    var allBooks: [Book] { collections.flatMap(\.books) }
    var videoBooks: [Book] { allBooks.filter(\.hasVideo) }
    var pageCount: Int { pages.count }

    /// A stable "word of the day" so the home screen teaches something new daily.
    var termOfTheDay: Term? {
        guard !glossary.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return glossary[day % glossary.count]
    }
}
