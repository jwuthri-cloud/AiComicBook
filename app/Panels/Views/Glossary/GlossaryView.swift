import SwiftUI

struct GlossaryView: View {
    @Environment(ContentStore.self) private var store
    @State private var filter = ""
    @State private var category: String?

    private var categories: [String] {
        var seen: [String] = []
        for t in store.glossary where !seen.contains(t.category) { seen.append(t.category) }
        return seen.sorted()
    }

    private var terms: [Term] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return store.glossary.filter { term in
            (category == nil || term.category == category) && (q.isEmpty || Self.matches(term, q))
        }
    }

    static func matches(_ term: Term, _ query: String) -> Bool {
        let fields = [term.term] + term.aka
        if fields.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        if query.count >= 4, term.short.localizedCaseInsensitiveContains(query) { return true }
        // Typo tolerance on the name itself.
        let q = query.lowercased()
        return query.count >= 4 && fields.contains { f in
            SearchEngine.editDistance(String(f.lowercased().prefix(q.count)), q, limit: 1) <= 1
        }
    }

    var body: some View {
        NavigationStack {
            let grouped = Dictionary(grouping: terms, by: \.sortLetter)
            let letters = grouped.keys.sorted()
            List {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip("All", selected: category == nil, tint: Theme.accent) { category = nil }
                            ForEach(categories, id: \.self) { c in
                                chip(c, selected: category == c, tint: Theme.categoryTint(c)) { category = category == c ? nil : c }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                ForEach(letters, id: \.self) { letter in
                    Section {
                        ForEach(grouped[letter] ?? []) { term in
                            NavigationLink(value: Route.term(term.id)) {
                                TermRow(term: term)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(letter)
                            .font(.serif(.title3, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Glossary")
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a word or acronym")
            .overlay {
                if terms.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            .withRoutes()
        }
    }

    private func chip(_ text: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? Theme.onTint : tint)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

struct TermRow: View {
    let term: Term
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(term.term)
                    .font(.serif(prominent ? .title3 : .headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                ForEach(term.aka.prefix(2), id: \.self) { aka in
                    Text(aka)
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Theme.categoryTint(term.category))
                        .lineLimit(1)
                }
            }
            Text(term.short)
                .font(.serif(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(prominent ? 3 : 2)
        }
        .padding(.vertical, 3)
    }
}

/// Lets a term sheet inside the reader jump to a page without leaving the reader.
private struct OpenPageKey: EnvironmentKey {
    static let defaultValue: ((Page) -> Void)? = nil
}

extension EnvironmentValues {
    var openPage: ((Page) -> Void)? {
        get { self[OpenPageKey.self] }
        set { self[OpenPageKey.self] = newValue }
    }
}

struct TermDetailView: View {
    let term: Term
    var isSheet = false
    var onOpenPage: ((Page) -> Void)? = nil

    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openPage) private var inheritedOpenPage
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        let tint = Theme.categoryTint(term.category)
        let open = onOpenPage ?? inheritedOpenPage
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Pill(text: term.category, tint: tint)
                    Text(term.term)
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !term.aka.isEmpty {
                        Text("Also: " + term.aka.joined(separator: " · "))
                            .font(.rounded(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Text(term.short)
                    .font(.serif(.title3).italic())
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 3) }

                Text(term.definition)
                    .font(.serif(.body))
                    .foregroundStyle(Theme.ink.opacity(0.88))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Button { asking = true } label: {
                    Label("Ask about this word", systemImage: "sparkles")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                let related = term.related.compactMap { store.terms[$0] }
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Related").font(.serif(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        FlowLayout(spacing: 8) {
                            ForEach(related) { r in
                                NavigationLink(value: Route.term(r.id)) {
                                    Text(r.term)
                                        .font(.rounded(.subheadline, weight: .medium))
                                        .foregroundStyle(Theme.categoryTint(r.category))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Theme.categoryTint(r.category).opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let pages = term.pages.compactMap { store.pages[$0] }
                if !pages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appears in \(pages.count) \(pages.count == 1 ? "page" : "pages")")
                            .font(.serif(.headline, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(pages) { page in
                                    Button {
                                        if let open { open(page) } else { router.read(page: page, in: store) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ContentImage(path: page.thumb)
                                                .frame(width: 96, height: 144)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                                            Text(page.title)
                                                .font(.serif(.caption, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(2)
                                            Text(store.book(for: page)?.title ?? "")
                                                .font(.rounded(.caption2))
                                                .foregroundStyle(Theme.inkTertiary)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 96, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -20)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openPage, open)
        .sheet(isPresented: $asking) {
            AssistantView(context: .term(term), onOpenPage: open)
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
