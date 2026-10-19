import Foundation
import Observation

/// Read-only library loaded from the bundled Content folder.
@Observable
final class ContentStore {
    let collections: [Collection]
    let glossary: [Term]
    let synonyms: [String: [String]]
    let quiz: [Question]
    let playbook: Playbook?
    let contentURL: URL

    private(set) var books: [String: Book] = [:]
    private(set) var pages: [String: Page] = [:]
    private(set) var terms: [String: Term] = [:]
    private(set) var collectionsById: [String: Collection] = [:]
    private(set) var toolsById: [String: Tool] = [:]

    @ObservationIgnored lazy var termMatcher = TermMatcher(terms: glossary)
    @ObservationIgnored lazy var search = SearchEngine(store: self)
    /// Undirected "related" links between glossary terms, best-connected first.
    @ObservationIgnored private lazy var termGraph: [String: [String]] = {
        var links: [String: Set<String>] = [:]
        for term in glossary {
            for other in term.related where terms[other] != nil && other != term.id {
                links[term.id, default: []].insert(other)
                links[other, default: []].insert(term.id)
            }
        }
        return links.mapValues { ids in
            ids.sorted { (links[$0]?.count ?? 0, $1) > (links[$1]?.count ?? 0, $0) }
        }
    }()

    func relatedTermIds(_ id: String) -> [String] { termGraph[id] ?? [] }

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
        playbook = file.playbook
        glossary = file.glossary.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        for collection in collections {
            collectionsById[collection.id] = collection
            for book in collection.books {
                books[book.id] = book
                for page in book.pages { pages[page.id] = page }
            }
        }
        for term in glossary { terms[term.id] = term }
        for tool in playbook?.tools ?? [] { toolsById[tool.id] = tool }
    }

    /// Experiment maps that use this tool somewhere in their tree.
    func experiments(using toolId: String) -> [Experiment] {
        func uses(_ nodes: [TreeNode]) -> Bool {
            nodes.contains { $0.tool == toolId || ($0.branches ?? []).contains { uses($0.then) } }
        }
        return (playbook?.experiments ?? []).filter { uses($0.tree) }
    }

    func url(_ relative: String) -> URL { contentURL.appendingPathComponent(relative) }

    func book(for page: Page) -> Book? { books[page.bookId] }
    func collection(for book: Book) -> Collection? { collectionsById[book.collectionId] }

    /// Glossary terms not worth highlighting in this book: Git words ("push", "merge") and data-structure
    /// words ("trie", "stack") read as plain English outside their own collections.
    func termsToSkip(in book: Book) -> Set<String> {
        let scoped: [String: Set<String>] = ["Git": ["swe"], "Software Engineering": ["swe"], "Algorithms": ["leetcode", "ml"], "Data Structures": ["leetcode", "ml"]]
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
