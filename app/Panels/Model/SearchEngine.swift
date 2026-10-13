import Foundation
import NaturalLanguage

/// Offline search over pages, books and glossary terms.
///
/// Ranking combines: weighted fields (title > keywords > headings > body), prefix matching while
/// typing, typo tolerance (edit distance), acronym/synonym expansion from the glossary, and a
/// meaning-based rerank with Apple's on-device sentence embeddings for natural-language questions.
final class SearchEngine {
    enum Kind: Int { case term, page, book }

    struct Hit: Identifiable {
        let kind: Kind
        let itemId: String
        let score: Double
        let matchedTokens: Set<String>
        var isSemantic = false
        var id: String { "\(kind.rawValue):\(itemId)" }
    }

    private struct Doc {
        let kind: Kind
        let id: String
        let title: String
        let semanticText: String
    }

    private struct Posting {
        let doc: Int
        let weight: Double
    }

    private var docs: [Doc] = []
    private var index: [String: [Posting]] = [:]
    private var vocabulary: [String] = []
    private var surfaceToStem: [String: String] = [:]
    private var surfaces: [String] = []
    private var idf: [String: Double] = [:]
    private var synonyms: [String: [String]] = [:]
    private var vectors: [[Double]?] = []
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let queue = DispatchQueue(label: "search.embeddings", qos: .utility)
    private var vectorsReady = false

    init(store: ContentStore) {
        for term in store.glossary {
            add(.term, term.id, title: term.term,
                fields: [(term.term, 8), (term.aka.joined(separator: " "), 8), (term.short, 2), (term.definition, 1), (term.category, 0.5)],
                semantic: "\(term.term). \(term.short)")
            // Acronym <-> expansion, so "rlhf" also finds "reinforcement learning from human feedback".
            let names = [term.term] + term.aka
            let tokenSets = names.map(Self.tokenize).filter { !$0.isEmpty }
            for tokens in tokenSets where tokens.count == 1 {
                let others = tokenSets.filter { $0 != tokens }.flatMap { $0 }
                if !others.isEmpty { synonyms[tokens[0], default: []] += others }
            }
        }
        for collection in store.collections {
            for book in collection.books {
                add(.book, book.id, title: book.title,
                    fields: [(book.title, 6), (book.subtitle, 2), (collection.title, 1.5), (book.objectives.joined(separator: " "), 1.5)],
                    semantic: "\(book.title). \(book.objectives.joined(separator: " "))")
                for page in book.pages {
                    var fields: [(String, Double)] = [
                        (page.title, 6), (page.printedTitle ?? "", 3), (page.subtitle, 3),
                        (page.keywords.joined(separator: " "), 4), (page.footer, 1.5), (page.summary, 1),
                        (book.title, 1), (page.wordKey, 1),
                    ]
                    for panel in page.panels {
                        fields.append((panel.heading, 2.5))
                        fields.append((panel.body, 1))
                        if let code = panel.code { fields.append((code, 0.5)) }
                    }
                    add(.page, page.id, title: page.title, fields: fields,
                        semantic: "\(page.title). \(page.subtitle). \(page.summary)")
                }
            }
        }
        vocabulary = Array(index.keys)
        let n = Double(docs.count)
        for (token, postings) in index {
            let df = Double(Set(postings.map(\.doc)).count)
            idf[token] = log(1 + (n - df + 0.5) / (df + 0.5))
        }
        for (word, phrases) in store.synonyms {
            let key = Self.tokenize(word).joined(separator: " ")
            guard !key.isEmpty else { continue }
            synonyms[key, default: []] += phrases.flatMap(Self.tokenize)
        }
        surfaces = Array(surfaceToStem.keys)
        vectors = Array(repeating: nil, count: docs.count)
        warmUpEmbeddings()
    }

    // MARK: Indexing

    private func add(_ kind: Kind, _ id: String, title: String, fields: [(String, Double)], semantic: String) {
        let doc = docs.count
        docs.append(Doc(kind: kind, id: id, title: title, semanticText: semantic))
        var weights: [String: Double] = [:]
        for (text, weight) in fields where weight > 0 {
            for surface in Self.surfaceWords(text) where surface.count >= 4 {
                surfaceToStem[surface] = Self.stem(surface)
            }
            for token in Self.tokenize(text) {
                // Saturating term frequency: repeated words help a little, not linearly.
                weights[token] = min((weights[token] ?? 0) + weight, weight * 2.2)
            }
        }
        for (token, weight) in weights {
            index[token, default: []].append(Posting(doc: doc, weight: weight))
        }
    }

    static func tokenize(_ text: String) -> [String] {
        surfaceWords(text).map(stem).filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    static func surfaceWords(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func stem(_ w: String) -> String {
        guard w.count > 4 else { return w }
        for suffix in ["ing", "ies", "es", "ed", "s"] where w.hasSuffix(suffix) && w.count - suffix.count >= 3 {
            if suffix == "ies" { return String(w.dropLast(3)) + "y" }
            if suffix == "s" && w.hasSuffix("ss") { return w }
            return String(w.dropLast(suffix.count))
        }
        return w
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "is", "are", "it", "its", "be", "by", "as",
        "at", "this", "that", "with", "from", "can", "do", "does", "what", "how", "why", "when", "who", "which",
        "about", "into", "than", "then", "there", "their", "they", "them", "you", "your", "we", "our", "i", "me",
        "my", "so", "if", "not", "but", "was", "were", "has", "have", "had", "will", "would", "should", "could",
    ]

    // MARK: Query

    func search(_ query: String, limit: Int = 60) -> [Hit] {
        let surfaceQuery = Self.surfaceWords(query).filter { !Self.stopWords.contains(Self.stem($0)) && !Self.stem($0).isEmpty }
        let tokens = surfaceQuery.map(Self.stem)
        guard !tokens.isEmpty else { return [] }

        var scores: [Int: Double] = [:]
        var matched: [Int: Set<String>] = [:]
        var coverage: [Int: Int] = [:]

        for (position, token) in tokens.enumerated() {
            let isLast = position == tokens.count - 1
            var expansions: [(String, Double)] = [(token, 1.0)]
            // While typing, the last word is probably incomplete.
            if token.count >= 2 {
                let prefixWeight = isLast ? 0.85 : 0.55
                expansions += vocabulary.lazy.filter { $0.count > token.count && $0.hasPrefix(token) }.prefix(40).map { ($0, prefixWeight) }
            }
            // Typos: compare what was typed with the words as written on the pages.
            let typed = surfaceQuery[position]
            if typed.count >= 4 && index[token] == nil {
                let maxDistance = typed.count >= 8 ? 2 : 1
                expansions += surfaces.lazy
                    .filter { abs($0.count - typed.count) <= maxDistance && $0.first == typed.first }
                    .filter { Self.editDistance($0, typed, limit: maxDistance) <= maxDistance }
                    .prefix(12).compactMap { self.surfaceToStem[$0].map { ($0, 0.6) } }
            }
            for synonym in synonyms[token] ?? [] where synonym != token { expansions.append((synonym, 0.65)) }

            var bestForDoc: [Int: Double] = [:]
            for (word, factor) in expansions {
                guard let postings = index[word] else { continue }
                let weight = (idf[word] ?? 1) * factor
                for p in postings {
                    let s = p.weight * weight
                    if s > (bestForDoc[p.doc] ?? 0) { bestForDoc[p.doc] = s }
                    matched[p.doc, default: []].insert(word)
                }
            }
            for (doc, s) in bestForDoc {
                scores[doc, default: 0] += s
                coverage[doc, default: 0] += 1
            }
        }

        let normalizedQuery = tokens.joined(separator: " ")
        var hits: [Hit] = scores.map { doc, score in
            let covered = Double(coverage[doc] ?? 0) / Double(tokens.count)
            var s = score * covered * covered
            let titleTokens = Self.tokenize(docs[doc].title).joined(separator: " ")
            if titleTokens == normalizedQuery { s *= 3 } else if titleTokens.hasPrefix(normalizedQuery) { s *= 1.8 }
            return Hit(kind: docs[doc].kind, itemId: docs[doc].id, score: s, matchedTokens: matched[doc] ?? [])
        }

        // Natural-language questions: blend in meaning-based similarity, but only for documents that
        // stand out from the crowd (sentence embeddings give every pair a fairly similar baseline).
        if tokens.count >= 3 || hits.count < 3, let semantic = semanticScores(for: query) {
            let top = hits.map(\.score).max() ?? 1
            var byDoc = Dictionary(uniqueKeysWithValues: hits.map { ($0.id, $0) })
            for (doc, z) in semantic where z > 2.2 {
                let boost = (z - 2.2) * 0.35 * max(top, 4)
                let key = "\(docs[doc].kind.rawValue):\(docs[doc].id)"
                if var hit = byDoc[key] {
                    hit = Hit(kind: hit.kind, itemId: hit.itemId, score: hit.score + boost, matchedTokens: hit.matchedTokens)
                    byDoc[key] = hit
                } else {
                    byDoc[key] = Hit(kind: docs[doc].kind, itemId: docs[doc].id, score: boost * 0.8, matchedTokens: [], isSemantic: true)
                }
            }
            hits = Array(byDoc.values)
        }

        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: Semantic

    private func warmUpEmbeddings() {
        guard let embedding else { return }
        let texts = docs.map(\.semanticText)
        queue.async { [weak self] in
            let computed = texts.map { embedding.vector(for: $0) }
            DispatchQueue.main.async {
                self?.vectors = computed
                self?.vectorsReady = true
            }
        }
    }

    private func semanticScores(for query: String) -> [(Int, Double)]? {
        guard vectorsReady, let embedding, let q = embedding.vector(for: query) else { return nil }
        let qn = sqrt(q.reduce(0) { $0 + $1 * $1 })
        guard qn > 0 else { return nil }
        var result: [(Int, Double)] = []
        for (i, v) in vectors.enumerated() {
            guard let v else { continue }
            var dot = 0.0, vn = 0.0
            for j in 0..<min(v.count, q.count) {
                dot += v[j] * q[j]
                vn += v[j] * v[j]
            }
            guard vn > 0 else { continue }
            result.append((i, dot / (qn * sqrt(vn))))
        }
        // Convert to z-scores so the threshold means "unusually close", whatever the baseline.
        let mean = result.map(\.1).reduce(0, +) / Double(max(result.count, 1))
        let variance = result.map { ($0.1 - mean) * ($0.1 - mean) }.reduce(0, +) / Double(max(result.count, 1))
        let sd = max(variance.squareRoot(), 1e-6)
        return result.map { ($0.0, ($0.1 - mean) / sd) }.sorted { $0.1 > $1.1 }.prefix(40).map { $0 }
    }

    // MARK: Helpers

    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            var rowMin = current[0]
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }

    /// Short excerpt around the first matched word, for result rows.
    static func snippet(from text: String, matching tokens: Set<String>, radius: Int = 70) -> String {
        guard !tokens.isEmpty else { return String(text.prefix(radius * 2)) }
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard let hit = words.firstIndex(where: { word in
            let t = tokenize(String(word)).filter { $0.count >= 3 }
            return t.contains(where: { tok in tokens.contains(where: { $0.count >= 3 && (tok.hasPrefix($0) || $0.hasPrefix(tok)) }) })
        }) else { return String(text.prefix(radius * 2)) }
        let start = max(0, hit - 6)
        let end = min(words.count, start + 26)
        var s = words[start..<end].joined(separator: " ")
        if start > 0 { s = "…" + s }
        if end < words.count { s += "…" }
        return s
    }
}
