import SwiftUI

struct ReaderView: View {
    let book: Book
    let startIndex: Int
    let initialMode: ReaderMode?

    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router
    @Environment(QuizState.self) private var quizState
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerMode") private var savedMode = ReaderMode.comic

    @State private var index = 0
    @State private var mode = ReaderMode.comic
    @State private var chromeVisible = true
    @State private var term: Term?
    @State private var zoomPage: Page?
    @State private var askRequest: AskRequest?
    @State private var isZoomed = false
    @State private var shareItem: ShareItem?
    @State private var zoomRegistry = ZoomRegistry()

    /// The assistant opened on this page, optionally with a question sent straight away.
    struct AskRequest: Identifiable {
        let id = UUID()
        let context: AssistantContext
        var prompt: String?
    }

    private var isListeningHere: Bool { listener.book?.id == book.id }

    private var page: Page { book.pages[index] }
    private var tint: Color { Theme.tint(store.collection(for: book)?.tint ?? "") }
    private var modes: [ReaderMode] { book.hasVideo ? ReaderMode.allCases : [.comic, .text] }

    var body: some View {
        ZStack {
            (mode == .text ? Theme.paper : Theme.background).ignoresSafeArea()

            PageCurlView(
                count: book.pages.count,
                index: $index,
                mode: mode,
                pagingEnabled: !isZoomed,
                makePage: { i, mode in
                    AnyView(
                        ReaderPage(
                            page: book.pages[i],
                            book: book,
                            mode: mode,
                            tint: tint,
                            onTerm: { term = $0 },
                            onZoom: { zoomPage = $0 },
                            onToggleChrome: { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } },
                            onChrome: { visible in
                                guard visible != chromeVisible else { return }
                                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = visible }
                            },
                            onZoomChange: { zoomed in
                                guard zoomed != isZoomed else { return }
                                isZoomed = zoomed
                                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = !zoomed }
                            },
                            onWatchBook: { watchBook(from: $0) },
                            zoomRegistry: zoomRegistry,
                            onAsk: { ask($0, page: book.pages[i]) },
                            onSharePanel: { share(panel: $0, page: book.pages[i]) }
                        )
                        .environment(store)
                        .environment(library)
                        .environment(listener)
                    )
                }
            )
            .ignoresSafeArea()

            if chromeVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .onAppear {
            index = startIndex
            let preferred = initialMode ?? savedMode
            mode = modes.contains(preferred) ? preferred : .comic
            library.open(book: book, at: startIndex)
        }
        .onChange(of: index) { _, new in
            library.open(book: book, at: new)
            isZoomed = false
        }
        .onChange(of: mode) { _, _ in isZoomed = false }
        .onChange(of: mode) { _, new in savedMode = new }
        // Listening to this book: the pages turn along with the voice.
        .onChange(of: listener.pageIndex) { _, new in
            if isListeningHere, new != index, book.pages.indices.contains(new) { index = new }
        }
        .sheet(item: $term) { term in
            NavigationStack { TermDetailView(term: term, isSheet: true, onOpenPage: { openPage($0) }).withRoutes() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $zoomPage) { page in
            ZoomViewer(page: page)
        }
        .sheet(item: $askRequest) { request in
            AssistantView(context: request.context, initialPrompt: request.prompt, onOpenPage: { openPage($0) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(item: item)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleStyle())
            .accessibilityLabel("Close")

            Spacer(minLength: 0)

            Picker("Mode", selection: $mode) {
                ForEach(modes) { m in
                    Image(systemName: m.symbol).tag(m).accessibilityLabel(m.label)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: CGFloat(modes.count) * 58)

            Spacer(minLength: 0)

            Menu {
                Button { ask(nil) } label: { Label("Ask a question", systemImage: "bubble.left.and.text.bubble.right") }
                Button { ask(Self.simplerPrompt) } label: { Label("Explain it simpler", systemImage: "sparkles") }
                Button { ask("Give me one concrete, real-world example of the main idea on this page, in under 120 words.") } label: {
                    Label("Real-world example", systemImage: "lightbulb")
                }
                Button { ask("Quiz me on this page: ask one question at a time, wait for my answer, then tell me if I'm right.") } label: {
                    Label("Quiz me on this page", systemImage: "questionmark.bubble")
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .accessibilityLabel("Ask or explain simpler")

            Button { toggleListening() } label: {
                Image(systemName: isListeningHere && listener.isPlaying ? "pause.fill" : "headphones")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isListeningHere ? tint : Theme.ink)
                    .frame(width: 38, height: 38)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(GlassCircleStyle())
            .accessibilityLabel(isListeningHere && listener.isPlaying ? "Pause listening" : "Listen from this page")

            Menu {
                Button { library.toggleBookmark(page) } label: {
                    Label(library.isBookmarked(page) ? "Remove bookmark" : "Bookmark page", systemImage: library.isBookmarked(page) ? "bookmark.slash" : "bookmark")
                }
                Button { sharePage() } label: {
                    Label(mode == .comic && isZoomed ? "Share this detail" : "Share page", systemImage: "square.and.arrow.up")
                }
                if mode == .comic {
                    Button { zoomPage = page } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                Button { listener.start(book, at: index, store: store) } label: { Label("Listen from this page", systemImage: "headphones") }
            } label: {
                Image(systemName: library.isBookmarked(page) ? "bookmark.fill" : "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(library.isBookmarked(page) ? tint : Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(page.title)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(book.title) · \(index + 1) of \(book.pages.count)")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            if book.pages.count > 1 {
                PageScrubber(count: book.pages.count, index: $index, tint: tint)
            }
            if isListeningHere {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, isActive: listener.isPlaying)
                    Text(listener.isPlaying ? "Reading aloud · page \(listener.pageIndex + 1)" : "Paused")
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Button { listener.stop() } label: {
                        Text("Stop").font(.rounded(.caption, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                }
                .transition(.opacity)
            }
            if index == book.pages.count - 1, store.quiz.contains(where: { $0.pageId.hasPrefix(book.id + "-") }) {
                Button { startQuiz() } label: {
                    Label("Finished? Test yourself", systemImage: "checkmark.seal.fill")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.onTint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    static let simplerPrompt = "Explain this page more simply, like I'm 12. Use one everyday analogy and keep it under 150 words."

    private func ask(_ prompt: String?, page: Page? = nil) {
        askRequest = AskRequest(context: .page(page ?? self.page, showingComic: mode == .comic), prompt: prompt)
    }

    private func toggleListening() {
        if isListeningHere {
            if listener.isPlaying { listener.pause() } else if listener.pageIndex == index { listener.resume() } else { listener.jump(to: index) }
        } else {
            listener.start(book, at: index, store: store)
        }
    }

    private func sharePage() {
        let collection = store.collection(for: book)
        if mode == .text, let first = page.panels.first, page.panels.count == 1 {
            shareItem = ShareCard.text(first, page: page, book: book, collection: collection)
            return
        }
        Task {
            let visible = zoomRegistry.visible(page.id)
            let image: UIImage? = if let visible { visible.image } else { await ImageCache.shared.load(store.url(page.image)) }
            guard let image else { return }
            shareItem = ShareCard.comic(image, page: page, book: book, collection: collection, isDetail: visible?.isDetail ?? false)
        }
    }

    private func share(panel: Panel, page: Page) {
        shareItem = ShareCard.text(panel, page: page, book: book, collection: store.collection(for: book))
    }

    private func openPage(_ target: Page) {
        term = nil
        if let i = book.pages.firstIndex(of: target) {
            index = i
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.read(page: target, in: store) }
        }
    }

    private func startQuiz() {
        let session = QuizBuilder(store: store, state: quizState).session(.book(book.id))
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.quiz = session }
    }

    private func watchBook(from page: Page) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.watch(book, from: page) }
    }
}

struct GlassCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Theme.hairline))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

/// Dots for short books, a slider for long ones.
struct PageScrubber: View {
    let count: Int
    @Binding var index: Int
    let tint: Color

    var body: some View {
        if count <= 12 {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? tint : Theme.inkTertiary.opacity(0.4))
                        .frame(width: i == index ? 22 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -8))
                        .onTapGesture { index = i }
                }
            }
            .animation(.snappy, value: index)
            .accessibilityElement()
            .accessibilityLabel("Page \(index + 1) of \(count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: index = min(index + 1, count - 1)
                case .decrement: index = max(index - 1, 0)
                @unknown default: break
                }
            }
        } else {
            Slider(
                value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                in: 0...Double(count - 1),
                step: 1
            )
            .tint(tint)
        }
    }
}
