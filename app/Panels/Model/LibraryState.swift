import Foundation
import Observation

/// The reader's own progress: where they are in each book, what they saved and searched.
@Observable
final class LibraryState {
    private struct Snapshot: Codable {
        var lastPage: [String: Int] = [:]
        var readPages: Set<String> = []
        var bookmarks: [String] = []
        var recentBooks: [String] = []
        var recentSearches: [String] = []
    }

    private var snapshot: Snapshot {
        didSet { save() }
    }

    private static let key = "library.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Progress

    func lastPageIndex(for book: Book) -> Int {
        min(snapshot.lastPage[book.id] ?? 0, max(book.pages.count - 1, 0))
    }

    func open(book: Book, at index: Int) {
        guard book.pages.indices.contains(index) else { return }
        var s = snapshot
        s.lastPage[book.id] = index
        s.readPages.insert(book.pages[index].id)
        s.recentBooks.removeAll { $0 == book.id }
        s.recentBooks.insert(book.id, at: 0)
        s.recentBooks = Array(s.recentBooks.prefix(12))
        snapshot = s
    }

    func isRead(_ page: Page) -> Bool { snapshot.readPages.contains(page.id) }

    func progress(of book: Book) -> Double {
        guard !book.pages.isEmpty else { return 0 }
        return Double(book.pages.filter(isRead).count) / Double(book.pages.count)
    }

    var recentBookIds: [String] { snapshot.recentBooks }
    var readPageCount: Int { snapshot.readPages.count }

    // MARK: Bookmarks

    func isBookmarked(_ page: Page) -> Bool { snapshot.bookmarks.contains(page.id) }

    func toggleBookmark(_ page: Page) {
        if let i = snapshot.bookmarks.firstIndex(of: page.id) {
            snapshot.bookmarks.remove(at: i)
        } else {
            snapshot.bookmarks.insert(page.id, at: 0)
        }
    }

    var bookmarkIds: [String] { snapshot.bookmarks }

    // MARK: Search history

    var recentSearches: [String] { snapshot.recentSearches }

    func remember(search: String) {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        var list = snapshot.recentSearches.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        snapshot.recentSearches = Array(list.prefix(8))
    }

    func clearSearches() { snapshot.recentSearches = [] }
}

/// App-wide navigation requests (open the reader from search, glossary, home…).
@Observable
final class Router {
    struct ReaderRequest: Identifiable, Equatable {
        let bookId: String
        let pageIndex: Int
        var mode: ReaderMode?
        var id: String { "\(bookId)#\(pageIndex)" }
    }

    struct PlayerRequest: Identifiable, Equatable {
        let bookId: String
        let startIndex: Int
        var id: String { "\(bookId)#\(startIndex)" }
    }

    var reader: ReaderRequest?
    var player: PlayerRequest?
    var term: Term?
    var quiz: QuizSession?
    var game: Game?
    var debugAsk = false
    var pendingSearch: String?
    /// Debug: open the concept map on this term.
    var pendingMap: String?
    var pendingRoute: Route?
    /// Debug / deep link: push this inside the Playbook tab.
    var pendingPlaybook: Route?
    var showWatch = false

    func read(_ book: Book, at index: Int = 0, mode: ReaderMode? = nil) {
        let request = ReaderRequest(bookId: book.id, pageIndex: index, mode: mode)
        // A sheet must close before a full-screen reader can appear.
        if term != nil {
            term = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.reader = request }
        } else {
            reader = request
        }
    }

    func read(page: Page, in store: ContentStore, mode: ReaderMode? = nil) {
        guard let book = store.book(for: page), let index = book.pages.firstIndex(of: page) else { return }
        read(book, at: index, mode: mode)
    }

    func watch(_ book: Book, from page: Page? = nil) {
        let clips = book.videoPages
        let start = page.flatMap { clips.firstIndex(of: $0) } ?? 0
        let request = PlayerRequest(bookId: book.id, startIndex: start)
        // The Watch sheet must close before the full-screen player can appear.
        if showWatch {
            showWatch = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.player = request }
        } else {
            player = request
        }
    }
}
