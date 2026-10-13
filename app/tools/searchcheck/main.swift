// Ranking check for the app's SearchEngine, run on the Mac:
//   swiftc -O app/Panels/Model/{Content,ContentStore,TermMatcher,SearchEngine}.swift app/tools/searchcheck/main.swift -o /tmp/searchcheck && /tmp/searchcheck "query" ...
import Foundation
import NaturalLanguage

let store = ContentStore(contentURL: URL(fileURLWithPath: "app/Panels/Content"))
let engine = store.search
print("sentence embedding available:", NLEmbedding.sentenceEmbedding(for: .english) != nil)
// Embeddings are computed in the background; give them a moment.
RunLoop.main.run(until: Date().addingTimeInterval(4))

for query in CommandLine.arguments.dropFirst() {
    print("\n== \(query)")
    for hit in engine.search(query).prefix(8) {
        let title: String
        switch hit.kind {
        case .term: title = "word  " + (store.terms[hit.itemId]?.term ?? "?")
        case .page: title = "page  " + (store.pages[hit.itemId].map { "\($0.title)  [\(store.book(for: $0)?.title ?? "")]" } ?? "?")
        case .book: title = "book  " + (store.books[hit.itemId]?.title ?? "?")
        }
        print(String(format: "%7.2f %@ %@", hit.score, hit.isSemantic ? "~" : " ", title))
    }
}
