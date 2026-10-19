import SwiftUI

struct HomeView: View {
    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var path = NavigationPath()

    private var recentBooks: [Book] { library.recentBookIds.compactMap { store.books[$0] } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    if recentBooks.isEmpty { startHere } else { continueReading }
                    watchLink
                    if let term = store.termOfTheDay { WordOfTheDay(term: term) }
                    ForEach(store.collections) { collection in
                        CollectionShelf(collection: collection)
                    }
                    if !library.bookmarkIds.isEmpty { bookmarksLink }
                    footer
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAssistant = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Ask the assistant")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAssistant) { AssistantView(context: .library) }
            .withRoutes()
            .onAppear {
                if let route = router.pendingRoute {
                    path.append(route)
                    router.pendingRoute = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.rounded(.caption, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkTertiary)
            Text(greeting)
                .font(.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("\(store.pageCount) illustrated pages · \(store.glossary.count) terms · all offline")
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 20)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var continueReading: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Continue", subtitle: "Pick up where you left off", symbol: "bookmark", tint: Theme.accent)
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(recentBooks.prefix(6)) { book in
                        ContinueCard(book: book)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var startHere: some View {
        if let guide = store.collections.first?.books.first {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Start here", subtitle: "A three-page field guide to research", symbol: "sparkles", tint: Theme.accent)
                ContinueCard(book: guide, isStart: true)
            }
            .padding(.horizontal, 20)
        }
    }

    /// Watch moved here when the Playbook took its tab.
    private var watchLink: some View {
        Button { router.showWatch = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .foregroundStyle(Theme.tint("teal"))
                    .frame(width: 40, height: 40)
                    .background(Theme.tint("teal").opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch").font(.serif(.headline)).foregroundStyle(Theme.ink)
                    Text("\(store.videoBooks.count) narrated books").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var bookmarksLink: some View {
        NavigationLink(value: Route.bookmarks) {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Theme.tint("coral"))
                    .frame(width: 40, height: 40)
                    .background(Theme.tint("coral").opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved pages").font(.serif(.headline)).foregroundStyle(Theme.ink)
                    Text("\(library.bookmarkIds.count) bookmarked").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        Text("Independent study guides. Proposed research is shown as proposals, not results.")
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.inkTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.top, 8)
    }
}

struct ContinueCard: View {
    let book: Book
    var isStart = false
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router
    @Environment(ContentStore.self) private var store

    var body: some View {
        let index = library.lastPageIndex(for: book)
        let page = book.pages[index]
        let tint = Theme.tint(store.collection(for: book)?.tint ?? "")
        Button { router.read(book, at: index) } label: {
            HStack(alignment: .top, spacing: 16) {
                BookCover(book: book, width: 84, showsProgress: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.collection(for: book)?.title.uppercased() ?? "")
                        .font(.rounded(.caption2, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(tint)
                    Text(book.title)
                        .font(.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(isStart ? "\(book.pages.count) pages · about \(book.pages.count * 2) min" : "Page \(index + 1) of \(book.pages.count) · \(page.title)")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack {
                        Label(isStart ? "Start reading" : "Resume", systemImage: "book.fill")
                            .font(.rounded(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.onTint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(tint, in: Capsule())
                        if !isStart {
                            Text("\(Int(library.progress(of: book) * 100))%")
                                .font(.rounded(.caption, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(width: isStart ? nil : 320, height: 158)
            .card(radius: 22)
        }
        .buttonStyle(.plain)
    }
}

struct WordOfTheDay: View {
    let term: Term
    @Environment(Router.self) private var router

    var body: some View {
        let tint = Theme.categoryTint(term.category)
        Button { router.term = term } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Word of the day", systemImage: "character.book.closed.fill")
                        .font(.rounded(.caption, weight: .bold))
                        .foregroundStyle(tint)
                    Spacer()
                    Pill(text: term.category, tint: tint)
                }
                Text(term.term)
                    .font(.serif(.title, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if !term.aka.isEmpty {
                    Text(term.aka.joined(separator: " · "))
                        .font(.rounded(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text(term.short)
                    .font(.serif(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

struct CollectionShelf: View {
    let collection: Collection

    var body: some View {
        let tint = Theme.tint(collection.tint)
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: Route.collection(collection.id)) {
                HStack(alignment: .center) {
                    SectionHeader(title: collection.title, subtitle: collection.subtitle, symbol: Theme.symbol(collection.symbol), tint: tint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(collection.books) { book in
                        NavigationLink(value: Route.book(book.id)) {
                            ShelfBook(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}
