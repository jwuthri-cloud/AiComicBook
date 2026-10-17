import Foundation
import Observation

/// A written question about one page (from app/content-src/quiz-*.json).
struct Question: Decodable, Identifiable, Hashable {
    let id: String
    let pageId: String
    let prompt: String
    let options: [String]
    let answer: Int
    let explanation: String
    let difficulty: Int
}

/// One question as shown in a session: options shuffled, linked to a page or a glossary term.
struct QuizItem: Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [String]
    let correct: Int
    let explanation: String
    let difficulty: Int
    let pageId: String?
    let termId: String?
}

enum QuizKind: Hashable {
    case daily
    case quick
    case review
    case words(category: String?)
    case book(String)
    case collection(String)
    case retry([String])

    var title: String {
        switch self {
        case .daily: "Daily 10"
        case .quick: "Quick 5"
        case .review: "Review"
        case .words: "Word drill"
        case .book: "Book quiz"
        case .collection: "Collection quiz"
        case .retry: "Second chance"
        }
    }
}

struct QuizSession: Identifiable, Equatable {
    let id = UUID()
    let kind: QuizKind
    let title: String
    let items: [QuizItem]

    static func == (a: QuizSession, b: QuizSession) -> Bool { a.id == b.id }
}

// MARK: - Progress

/// Spaced repetition (Leitner boxes) plus streaks, stored on the device.
@Observable
final class QuizState {
    struct Record: Codable {
        var box = 0
        var seen = 0
        var correct = 0
        var last: Date = .distantPast
    }

    private struct Snapshot: Codable {
        var records: [String: Record] = [:]
        var activeDays: [String] = []
        var dailyDone: String?
        var xp = 0
        var sessions = 0
    }

    private var snapshot: Snapshot {
        didSet { save() }
    }

    private static let key = "quiz.v1"
    /// Days until a question in each box comes back.
    static let intervals: [Double] = [0, 1, 3, 7, 21]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func record(_ id: String) -> Record? { snapshot.records[id] }

    func answer(_ item: QuizItem, correct: Bool) {
        mark(item.id, correct: correct, points: 10 + 5 * (item.difficulty - 1))
    }

    /// Records an answer from any practice mode (quiz, flashcards, games) in the same spaced-repetition boxes.
    func mark(_ id: String, correct: Bool, points: Int = 10) {
        var r = snapshot.records[id] ?? Record()
        r.seen += 1
        r.last = .now
        if correct {
            r.correct += 1
            r.box = min(r.box + 1, Self.intervals.count - 1)
        } else {
            r.box = 0
        }
        snapshot.records[id] = r
        if correct { snapshot.xp += points }
    }

    /// Bonus points for games, without touching review boxes.
    func award(_ points: Int) { snapshot.xp += max(0, points) }

    /// A finished game or flashcard deck counts towards the streak, like a quiz.
    func practiced() {
        let today = Self.dayKey(.now)
        guard !snapshot.activeDays.contains(today) else { return }
        snapshot.activeDays.append(today)
    }

    func finish(_ session: QuizSession) {
        let today = Self.dayKey(.now)
        var s = snapshot
        if !s.activeDays.contains(today) { s.activeDays.append(today) }
        s.activeDays = Array(s.activeDays.suffix(400))
        if session.kind == .daily { s.dailyDone = today }
        s.sessions += 1
        snapshot = s
    }

    var dailyDoneToday: Bool { snapshot.dailyDone == Self.dayKey(.now) }
    var xp: Int { snapshot.xp }

    /// Consecutive days with a finished quiz, counting today or yesterday as the latest.
    var streak: Int {
        let days = Set(snapshot.activeDays)
        var date = Date.now
        if !days.contains(Self.dayKey(date)) {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        var count = 0
        while days.contains(Self.dayKey(date)) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    var answeredCount: Int { snapshot.records.values.reduce(0) { $0 + $1.seen } }

    var accuracy: Double? {
        let seen = snapshot.records.values.reduce(0) { $0 + $1.seen }
        guard seen > 0 else { return nil }
        return Double(snapshot.records.values.reduce(0) { $0 + $1.correct }) / Double(seen)
    }

    func isMastered(_ id: String) -> Bool { (snapshot.records[id]?.box ?? 0) >= 3 }

    func isDue(_ id: String) -> Bool {
        guard let r = snapshot.records[id] else { return false }
        return Date.now.timeIntervalSince(r.last) >= Self.intervals[r.box] * 86_400
    }

    /// Questions answered wrong last time (box 0) or due again.
    func needsReview(_ id: String) -> Bool {
        guard let r = snapshot.records[id] else { return false }
        return r.box == 0 || isDue(id)
    }

    func resetProgress() { snapshot = Snapshot() }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

// MARK: - Building sessions

/// Turns the question bank (and the glossary) into sessions.
struct QuizBuilder {
    let store: ContentStore
    let state: QuizState

    /// All page questions plus two generated questions per glossary term.
    var pageItems: [QuizItem] { store.quiz.map(item) }

    func items(forBook id: String) -> [QuizItem] {
        guard let book = store.books[id] else { return [] }
        let pageIds = Set(book.pages.map(\.id))
        return store.quiz.filter { pageIds.contains($0.pageId) }.map(item)
    }

    func items(forCollection id: String) -> [QuizItem] {
        guard let c = store.collectionsById[id] else { return [] }
        let pageIds = Set(c.books.flatMap(\.pages).map(\.id))
        return store.quiz.filter { pageIds.contains($0.pageId) }.map(item)
    }

    func mastery(of items: [QuizItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { state.isMastered($0.id) }.count) / Double(items.count)
    }

    func session(_ kind: QuizKind) -> QuizSession {
        switch kind {
        case .daily:
            var rng = SeededGenerator(seed: stableHash(QuizState.dayKey(.now)))
            let pages = pick(pageItems, count: 8, using: &rng)
            let words = pick(termItems(category: nil), count: 2, using: &rng)
            return QuizSession(kind: kind, title: "Daily 10", items: (pages + words).shuffled(using: &rng))
        case .quick:
            var rng = SystemRandomNumberGenerator()
            return QuizSession(kind: kind, title: "Quick 5", items: pick(pageItems + termItems(category: nil), count: 5, using: &rng))
        case .review:
            let due = (pageItems + termItems(category: nil)).filter { state.needsReview($0.id) }
            return QuizSession(kind: kind, title: "Review", items: Array(due.shuffled().prefix(12)))
        case .words(let category):
            var rng = SystemRandomNumberGenerator()
            return QuizSession(kind: kind, title: category.map { "\($0) words" } ?? "Word drill", items: pick(termItems(category: category), count: 10, using: &rng))
        case .book(let id):
            var rng = SystemRandomNumberGenerator()
            let all = items(forBook: id)
            // Short books: everything, in reading order. Long books: a weighted sample.
            let chosen = all.count <= 15 ? all.sorted { order($0) < order($1) } : pick(all, count: 12, using: &rng)
            return QuizSession(kind: kind, title: store.books[id]?.title ?? "Book quiz", items: chosen)
        case .collection(let id):
            var rng = SystemRandomNumberGenerator()
            return QuizSession(kind: kind, title: store.collectionsById[id]?.title ?? "Quiz", items: pick(items(forCollection: id), count: 12, using: &rng))
        case .retry(let ids):
            let all = Dictionary(uniqueKeysWithValues: (pageItems + termItems(category: nil)).map { ($0.id, $0) })
            return QuizSession(kind: kind, title: "Second chance", items: ids.compactMap { all[$0] }.map(reshuffled))
        }
    }

    // MARK: Helpers

    private func item(_ q: Question) -> QuizItem {
        let order = Array(q.options.indices).shuffled()
        let isTrueFalse = q.options == ["True", "False"]
        let options = isTrueFalse ? q.options : order.map { q.options[$0] }
        let correct = isTrueFalse ? q.answer : order.firstIndex(of: q.answer)!
        return QuizItem(id: q.id, prompt: q.prompt, options: options, correct: correct,
                        explanation: q.explanation, difficulty: q.difficulty, pageId: q.pageId, termId: nil)
    }

    private func reshuffled(_ i: QuizItem) -> QuizItem {
        guard i.options != ["True", "False"] else { return i }
        let order = Array(i.options.indices).shuffled()
        return QuizItem(id: i.id, prompt: i.prompt, options: order.map { i.options[$0] }, correct: order.firstIndex(of: i.correct)!,
                        explanation: i.explanation, difficulty: i.difficulty, pageId: i.pageId, termId: i.termId)
    }

    private func order(_ i: QuizItem) -> String { i.pageId.map { "\($0)#\(i.id)" } ?? i.id }

    /// Glossary questions: "which word matches this definition?" and the reverse.
    func termItems(category: String?) -> [QuizItem] {
        let pool = store.glossary.filter { category == nil || $0.category == category }
        var result: [QuizItem] = []
        for term in pool {
            var siblings = store.glossary.filter { $0.category == term.category && $0.id != term.id && !term.related.contains($0.id) }
            if siblings.count < 3 { siblings = store.glossary.filter { $0.id != term.id } }
            // Stable distractors per term so a question reads the same each time it comes back.
            var rng = SeededGenerator(seed: stableHash(term.id))
            let distractors = Array(siblings.shuffled(using: &rng).prefix(3))
            let names = ([term] + distractors).map(\.term).shuffled()
            result.append(QuizItem(
                id: "term:\(term.id):name", prompt: "Which word means: “\(term.short)”",
                options: names, correct: names.firstIndex(of: term.term)!,
                explanation: term.definition, difficulty: 1, pageId: term.pages.first, termId: term.id))
            let shorts = ([term] + distractors).map(\.short).shuffled()
            result.append(QuizItem(
                id: "term:\(term.id):meaning", prompt: "What does “\(term.term)” mean?",
                options: shorts, correct: shorts.firstIndex(of: term.short)!,
                explanation: term.definition, difficulty: 2, pageId: term.pages.first, termId: term.id))
        }
        return result
    }

    /// Weighted sample: wrong answers and due questions first, then unseen, then the rest.
    private func pick<R: RandomNumberGenerator>(_ items: [QuizItem], count: Int, using rng: inout R) -> [QuizItem] {
        let weighted = items.map { item -> (QuizItem, Double) in
            let w: Double
            if let r = state.record(item.id) {
                w = r.box == 0 ? 5 : (state.isDue(item.id) ? 3 : 0.3)
            } else {
                w = 2.5
            }
            // Exponential keys give weighted sampling without replacement.
            return (item, -log(Double.random(in: 0.0001...1, using: &rng)) / w)
        }
        var chosen: [QuizItem] = []
        var pagesUsed = Set<String>()
        for (item, _) in weighted.sorted(by: { $0.1 < $1.1 }) {
            // Spread questions across pages.
            if let page = item.pageId, item.termId == nil {
                if pagesUsed.contains(page) && items.count > count * 2 { continue }
                pagesUsed.insert(page)
            }
            chosen.append(item)
            if chosen.count == count { break }
        }
        return chosen
    }
}

/// Deterministic randomness so the daily quiz is the same all day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a: unlike `hashValue`, the same string gives the same number on every launch.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    for byte in s.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x100000001B3
    }
    return h
}
