import SwiftUI

struct ReaderView: View {
    let book: Book
    let startIndex: Int
    let initialMode: ReaderMode?

    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router
    @Environment(QuizState.self) private var quizState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerMode") private var savedMode = ReaderMode.comic

    @State private var index = 0
    @State private var mode = ReaderMode.comic
    @State private var chromeVisible = true
    @State private var term: Term?
    @State private var zoomPage: Page?
    @State private var askContext: AssistantContext?
    @State private var isZoomed = false

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
                            onWatchBook: { watchBook(from: $0) }
                        )
                        .environment(store)
                        .environment(library)
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
        .sheet(item: $term) { term in
            NavigationStack { TermDetailView(term: term, isSheet: true, onOpenPage: { openPage($0) }).withRoutes() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $zoomPage) { page in
            ZoomViewer(page: page)
        }
        .sheet(item: $askContext) { context in
            AssistantView(context: context, onOpenPage: { openPage($0) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
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

            if mode == .comic {
                Button { zoomPage = page } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(GlassCircleStyle())
                .accessibilityLabel("Open full screen")
            }

            Button { askContext = .page(page, showingComic: mode == .comic) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleStyle())
            .accessibilityLabel("Ask about this page")

            Button { library.toggleBookmark(page) } label: {
                Image(systemName: library.isBookmarked(page) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(library.isBookmarked(page) ? tint : Theme.ink)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleStyle())
            .accessibilityLabel(library.isBookmarked(page) ? "Remove bookmark" : "Bookmark page")
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
