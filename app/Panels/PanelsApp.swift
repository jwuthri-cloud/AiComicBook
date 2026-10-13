import AVFoundation
import SwiftUI
import UIKit

@main
struct PanelsApp: App {
    @State private var store = ContentStore()
    @State private var library = LibraryState()
    @State private var router = Router()
    @State private var quizState = QuizState()
    @AppStorage("appearance") private var appearance = Appearance.system

    init() {
        // Videos keep playing with the silent switch on (gym, train).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        // Serif navigation titles, matching the book typography.
        func serif(_ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let descriptor = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: 0)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(.largeTitle), .foregroundColor: UIColor(Theme.ink)]
        bar.titleTextAttributes = [.font: serif(.headline), .foregroundColor: UIColor(Theme.ink)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(library)
                .environment(router)
                .environment(quizState)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTab: Hashable { case library, watch, quiz, glossary, search }

struct RootView: View {
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(QuizState.self) private var quizState
    @State private var tab = AppTab.library

    var body: some View {
        @Bindable var router = router
        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical", value: .library) {
                HomeView()
            }
            Tab("Watch", systemImage: "play.rectangle.on.rectangle", value: .watch) {
                WatchView()
            }
            Tab("Quiz", systemImage: "checkmark.seal", value: .quiz) {
                QuizHomeView()
            }
            Tab("Glossary", systemImage: "character.book.closed", value: .glossary) {
                GlossaryView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .fullScreenCover(item: $router.reader) { request in
            if let book = store.books[request.bookId] {
                ReaderView(book: book, startIndex: request.pageIndex, initialMode: request.mode)
            }
        }
        .fullScreenCover(item: $router.player) { request in
            if let book = store.books[request.bookId] {
                BookPlayerView(book: book, startIndex: request.startIndex)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $router.debugAsk) { AssistantView(context: .library) }
        .fullScreenCover(item: $router.quiz) { session in
            QuizSessionView(session: session)
        }
        .onAppear(perform: openDebugScreen)
        .sheet(item: $router.term) { term in
            NavigationStack {
                TermDetailView(term: term, isSheet: true)
                    .withRoutes()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

extension RootView {
    /// Debug builds only: PANELS_SCREEN opens a screen at launch, for screenshots and UI checks.
    /// e.g. "reader:fellowship-01-eval-gaming:0:text", "search:reward hacking", "glossary", "watch", "term:sparse-autoencoder".
    func openDebugScreen() {
        #if DEBUG
        // PANELS_KEYCHAIN_TEST=set|clear checks that the API key survives relaunches.
        switch ProcessInfo.processInfo.environment["PANELS_KEYCHAIN_TEST"] {
        case "set":
            KeyStore.openAIKey = "sk-test-123"
            print("keychain:", KeyStore.openAIKey ?? "nil")
        case "clear":
            KeyStore.openAIKey = nil
            print("keychain:", KeyStore.openAIKey ?? "nil")
        default: break
        }
        guard let spec = ProcessInfo.processInfo.environment["PANELS_SCREEN"], !spec.isEmpty else { return }
        let parts = spec.split(separator: ":", maxSplits: 3).map(String.init)
        switch parts.first {
        case "reader":
            if parts.count >= 3, let book = store.books[parts[1]] {
                router.read(book, at: Int(parts[2]) ?? 0, mode: parts.count > 3 ? ReaderMode(rawValue: parts[3]) : nil)
            }
        case "search":
            tab = .search
            router.pendingSearch = parts.count > 1 ? parts[1] : nil
        case "play":
            if parts.count > 1, let book = store.books[parts[1]] { router.watch(book) }
        case "quiz":
            tab = .quiz
            if parts.count > 1 {
                let builder = QuizBuilder(store: store, state: quizState)
                switch parts[1] {
                case "daily": router.quiz = builder.session(.daily)
                case "words": router.quiz = builder.session(.words(category: nil))
                default: router.quiz = builder.session(.book(parts[1]))
                }
            }
        case "ask":
            router.pendingRoute = nil
            router.debugAsk = true
        case "glossary": tab = .glossary
        case "watch": tab = .watch
        case "term":
            if parts.count > 1 { router.term = store.terms[parts[1]] }
        case "book":
            if parts.count > 1 { router.pendingRoute = .book(parts[1]) }
        default: break
        }
        #endif
    }
}

/// Destinations pushed inside each tab's NavigationStack.
enum Route: Hashable {
    case collection(String)
    case book(String)
    case term(String)
    case bookmarks
}

struct RouteDestinations: ViewModifier {
    @Environment(ContentStore.self) private var store

    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .collection(let id):
                if let c = store.collectionsById[id] { CollectionView(collection: c) }
            case .book(let id):
                if let b = store.books[id] { BookDetailView(book: b) }
            case .term(let id):
                if let t = store.terms[id] { TermDetailView(term: t) }
            case .bookmarks:
                BookmarksView()
            }
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }
}
