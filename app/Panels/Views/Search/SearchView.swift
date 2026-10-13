import SwiftUI

struct SearchView: View {
    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var hits: [SearchEngine.Hit] = []
    @State private var scope = Scope.all

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", pages = "Pages", words = "Words", books = "Books"
        var id: String { rawValue }
    }

    private let suggestions = [
        "How can a model cheat on its tests?", "RLHF", "sliding window", "What is a probe?",
        "sparse autoencoder", "git rebase", "why freeze the monitor", "dynamic programming",
    ]

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    idle
                } else {
                    results
                }
            }
            .background(Theme.background)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Pages, ideas, words…")
            .onSubmit(of: .search) { library.remember(search: query) }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                hits = store.search.search(query)
            }
            .withRoutes()
            .onAppear {
                if let pending = router.pendingSearch {
                    query = pending
                    router.pendingSearch = nil
                }
            }
        }
    }

    // MARK: Idle state

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !library.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent").font(.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Clear") { library.clearSearches() }.font(.rounded(.subheadline))
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(library.recentSearches, id: \.self) { q in
                                Button { query = q } label: {
                                    Label(q, systemImage: "clock.arrow.circlepath")
                                        .font(.rounded(.subheadline))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Theme.surface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.hairline))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Try asking").font(.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("Search understands typos, acronyms and plain questions.")
                        .font(.rounded(.subheadline)).foregroundStyle(Theme.inkSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { query = s } label: {
                                Text(s)
                                    .font(.serif(.subheadline))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Theme.accent.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Browse").font(.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(store.collections) { c in
                            NavigationLink(value: Route.collection(c.id)) {
                                CollectionTile(collection: c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Results

    private var filtered: [SearchEngine.Hit] {
        switch scope {
        case .all: hits
        case .pages: hits.filter { $0.kind == .page }
        case .words: hits.filter { $0.kind == .term }
        case .books: hits.filter { $0.kind == .book }
        }
    }

    private var results: some View {
        List {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

            let items = filtered
            if items.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                if scope == .all, let top = items.first {
                    Section {
                        row(for: top, prominent: true)
                    } header: {
                        Text("Top result")
                    }
                }
                let rest = scope == .all ? Array(items.dropFirst()) : items
                let words = rest.filter { $0.kind == .term && !$0.isSemantic }
                let pages = rest.filter { $0.kind == .page && !$0.isSemantic }
                let books = rest.filter { $0.kind == .book && !$0.isSemantic }
                let related = rest.filter(\.isSemantic)
                if !words.isEmpty { Section("Words") { ForEach(words.prefix(8)) { row(for: $0) } } }
                if !pages.isEmpty { Section("Pages") { ForEach(pages.prefix(30)) { row(for: $0) } } }
                if !books.isEmpty { Section("Books") { ForEach(books.prefix(6)) { row(for: $0) } } }
                if !related.isEmpty {
                    Section {
                        ForEach(related.prefix(10)) { row(for: $0) }
                    } header: {
                        Text("Related ideas")
                    } footer: {
                        Text("Matched by meaning rather than exact words.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func row(for hit: SearchEngine.Hit, prominent: Bool = false) -> some View {
        switch hit.kind {
        case .term:
            if let term = store.terms[hit.itemId] {
                Button {
                    library.remember(search: query)
                    router.term = term
                } label: {
                    TermRow(term: term, prominent: prominent)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
            }
        case .page:
            if let page = store.pages[hit.itemId] {
                Button {
                    library.remember(search: query)
                    router.read(page: page, in: store)
                } label: {
                    SearchPageRow(page: page, tokens: hit.matchedTokens, prominent: prominent)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
            }
        case .book:
            if let book = store.books[hit.itemId] {
                NavigationLink(value: Route.book(book.id)) {
                    HStack(spacing: 14) {
                        BookCover(book: book, width: 44, showsProgress: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title).font(.serif(.headline)).foregroundStyle(Theme.ink)
                            Text("\(store.collection(for: book)?.title ?? "") · \(book.pages.count) pages")
                                .font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
        }
    }
}

struct SearchPageRow: View {
    let page: Page
    let tokens: Set<String>
    var prominent = false
    @Environment(ContentStore.self) private var store

    var body: some View {
        let source = ([page.subtitle, page.summary] + page.panels.map(\.body)).joined(separator: " ")
        HStack(alignment: .top, spacing: 14) {
            ContentImage(path: page.thumb)
                .frame(width: prominent ? 70 : 50, height: prominent ? 105 : 75)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.book(for: page)?.title ?? "")
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                Text(page.title)
                    .font(.serif(prominent ? .title3 : .headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(highlighted(SearchEngine.snippet(from: source, matching: tokens)))
                    .font(.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(prominent ? 4 : 3)
            }
        }
        .padding(.vertical, 4)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for word in text.split(separator: " ") {
            let tokenized = SearchEngine.tokenize(String(word)).filter { $0.count >= 3 }
            guard tokenized.contains(where: { t in tokens.contains(where: { $0.count >= 3 && (t.hasPrefix($0) || $0.hasPrefix(t)) }) }),
                  let range = attributed.range(of: String(word)) else { continue }
            attributed[range].foregroundColor = Theme.ink
            attributed[range].font = .serif(.subheadline, weight: .bold)
        }
        return attributed
    }
}

struct CollectionTile: View {
    let collection: Collection
    var body: some View {
        let tint = Theme.tint(collection.tint)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: Theme.symbol(collection.symbol))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            Text(collection.title)
                .font(.serif(.headline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(collection.pageCount) pages")
                .font(.rounded(.caption))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }
}
