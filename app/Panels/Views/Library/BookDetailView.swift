import SwiftUI

struct BookDetailView: View {
    let book: Book
    @Environment(ContentStore.self) private var store
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router
    @Environment(QuizState.self) private var quizState
    @Environment(Listener.self) private var listener

    var body: some View {
        let collection = store.collection(for: book)
        let tint = Theme.tint(collection?.tint ?? "")
        let resume = library.lastPageIndex(for: book)
        let started = library.progress(of: book) > 0

        ScrollView {
            VStack(spacing: 0) {
                hero(tint: tint, collection: collection)

                VStack(alignment: .leading, spacing: 28) {
                    actions(tint: tint, resume: resume, started: started)
                    quizCard(tint: tint)

                    if !book.objectives.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What you'll learn")
                                .font(.serif(.title3, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            ForEach(book.objectives, id: \.self) { objective in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                                    Text(objective)
                                        .font(.serif(.body))
                                        .foregroundStyle(Theme.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pages")
                            .font(.serif(.title3, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, 8)
                        ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, page in
                            Button { router.read(book, at: index) } label: {
                                PageRow(page: page)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if index < book.pages.count - 1 { Divider().overlay(Theme.hairline) }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func hero(tint: Color, collection: Collection?) -> some View {
        VStack(spacing: 14) {
                BookCover(book: book, width: 150, showsProgress: false)
                VStack(spacing: 6) {
                    Text(collection?.title.uppercased() ?? "")
                        .font(.rounded(.caption, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                    Text(book.title)
                        .font(.serif(.title, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(book.subtitle)
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 30)
                HStack(spacing: 8) {
                    Pill(text: "\(book.pages.count) pages", symbol: "doc.richtext", tint: tint)
                    if book.hasVideo {
                        Pill(text: formatDuration(book.totalDuration), symbol: "play.fill", tint: tint)
                    }
                }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // Blurred cover glow that runs up under the navigation bar.
            ContentImage(path: book.cover)
                .frame(height: 560)
                .frame(maxWidth: .infinity)
                .blur(radius: 40)
                .opacity(0.5)
                .overlay(LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .center, endPoint: .bottom))
                .offset(y: -170)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func quizCard(tint: Color) -> some View {
        let builder = QuizBuilder(store: store, state: quizState)
        let items = builder.items(forBook: book.id)
        if !items.isEmpty {
            Button { router.quiz = builder.session(.book(book.id)) } label: {
                HStack(spacing: 14) {
                    MasteryRing(value: builder.mastery(of: items), tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test yourself")
                            .font(.serif(.headline, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(items.count) questions on this book · \(items.filter { quizState.isMastered($0.id) }.count) mastered")
                            .font(.rounded(.caption))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary)
                }
                .padding(14)
                .card(radius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private func actions(tint: Color, resume: Int, started: Bool) -> some View {
        HStack(spacing: 12) {
            Button { router.read(book, at: resume) } label: {
                Label(started ? "Continue · p.\(resume + 1)" : "Read", systemImage: "book.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle(tint: tint))

            if book.hasVideo {
                Button { router.watch(book) } label: {
                    Label("Watch", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
            } else {
                Button { router.read(book, at: resume, mode: .text) } label: {
                    Label("Read as text", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
            }

            Button {
                if listener.book?.id == book.id { listener.toggle() } else { listener.start(book, at: resume, store: store) }
            } label: {
                Image(systemName: listener.book?.id == book.id && listener.isPlaying ? "pause.fill" : "headphones")
                    .frame(width: 26)
                    .padding(.horizontal, 2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
            .accessibilityLabel("Listen")
        }
    }
}

struct FilledButtonStyle: ButtonStyle {
    var tint: Color
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(.headline, weight: .semibold))
            .foregroundStyle(secondary ? tint : Theme.onTint)
            .padding(.vertical, 14)
            .background(secondary ? tint.opacity(0.14) : tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct PageRow: View {
    let page: Page
    var showsBook = false
    @Environment(LibraryState.self) private var library
    @Environment(ContentStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ContentImage(path: page.thumb)
                .frame(width: 58, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(showsBook ? (store.book(for: page)?.title ?? "") : "Page \(page.number)")
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                    if page.video != nil {
                        Image(systemName: "play.circle.fill").font(.caption).foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer(minLength: 0)
                    if library.isRead(page) {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                Text(page.title)
                    .font(.serif(.headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(page.subtitle.isEmpty ? page.summary : page.subtitle)
                    .font(.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(Rectangle())
    }
}
