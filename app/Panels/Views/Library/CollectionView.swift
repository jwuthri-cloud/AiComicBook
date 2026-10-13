import SwiftUI

struct CollectionView: View {
    let collection: Collection

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 18, alignment: .top)]

    var body: some View {
        let tint = Theme.tint(collection.tint)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: Theme.symbol(collection.symbol))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 58, height: 58)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    Text(collection.title)
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(collection.description)
                        .font(.serif(.body))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Pill(text: "\(collection.books.count) books", symbol: "books.vertical", tint: tint)
                        Pill(text: "\(collection.pageCount) pages", symbol: "doc.richtext", tint: tint)
                        if collection.books.contains(where: \.hasVideo) {
                            Pill(text: "Videos", symbol: "play.fill", tint: tint)
                        }
                    }
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(collection.books) { book in
                        NavigationLink(value: Route.book(book.id)) {
                            ShelfBook(book: book, width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BookmarksView: View {
    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let pages = library.bookmarkIds.compactMap { store.pages[$0] }
        List {
            ForEach(pages) { page in
                Button { router.read(page: page, in: store) } label: {
                    PageRow(page: page, showsBook: true)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
                .swipeActions {
                    Button(role: .destructive) { library.toggleBookmark(page) } label: { Label("Remove", systemImage: "bookmark.slash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Saved pages")
        .overlay {
            if pages.isEmpty {
                ContentUnavailableView("No saved pages", systemImage: "bookmark", description: Text("Tap the bookmark while reading to keep a page here."))
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("textScale") private var textScale = 1.0
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryState.self) private var library

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $textScale, in: 0.85...1.6, step: 0.05)
                            Image(systemName: "textformat.size.larger")
                        }
                        Text("Reinforcement learning from human feedback is like practising with a coach.")
                            .font(.system(size: 18 * textScale, design: .serif))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Reading text size")
                }
                AssistantSettingsSection()
                Section("Your progress") {
                    LabeledContent("Pages read", value: "\(library.readPageCount)")
                    LabeledContent("Saved pages", value: "\(library.bookmarkIds.count)")
                    Button("Clear search history", role: .destructive) { library.clearSearches() }
                }
                Section {
                    Text("Everything in Panels is stored on this device, so it works without a connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
