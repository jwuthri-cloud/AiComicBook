import SwiftUI

struct QuizHomeView: View {
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(Router.self) private var router

    private var builder: QuizBuilder { QuizBuilder(store: store, state: state) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quiz")
                            .font(.serif(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("\(store.quiz.count) questions on every page, plus \(store.glossary.count * 2) word questions. Missed ones come back until they stick.")
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    stats
                    daily
                    quickModes
                    VStack(alignment: .leading, spacing: 14) {
                        Text("By collection")
                            .font(.serif(.title2, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        ForEach(store.collections) { collection in
                            NavigationLink(value: QuizRoute.collection(collection.id)) {
                                CollectionQuizRow(collection: collection, items: builder.items(forCollection: collection.id), mastery: builder.mastery(of:))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationDestination(for: QuizRoute.self) { route in
                switch route {
                case .collection(let id):
                    if let c = store.collectionsById[id] { CollectionQuizView(collection: c) }
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(state.streak)", label: state.streak == 1 ? "day streak" : "day streak", symbol: "flame.fill", tint: Theme.tint("coral"))
            StatTile(value: state.accuracy.map { "\(Int($0 * 100))%" } ?? "–", label: "accuracy", symbol: "target", tint: Theme.tint("teal"))
            StatTile(value: "\(state.xp)", label: "points", symbol: "star.fill", tint: Theme.tint("amber"))
        }
    }

    private var daily: some View {
        let tint = Theme.tint("violet")
        let done = state.dailyDoneToday
        return Button { router.quiz = builder.session(done ? .quick : .daily) } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(done ? "Done for today" : "Today's quiz", systemImage: done ? "checkmark.seal.fill" : "calendar")
                        .font(.rounded(.caption, weight: .bold))
                        .foregroundStyle(tint)
                    Text(done ? "Bonus round" : "Daily 10")
                        .font(.serif(.title, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(done ? "Five more questions while you have a minute." : "Eight page questions and two words, picked to fill the gaps.")
                        .font(.serif(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 56, height: 56)
                    .background(tint, in: Circle())
                    .shadow(color: tint.opacity(0.4), radius: 10, y: 4)
            }
            .padding(20)
            .background(
                LinearGradient(colors: [tint.opacity(0.2), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var quickModes: some View {
        let reviewCount = (builder.pageItems + builder.termItems(category: nil)).filter { state.needsReview($0.id) }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ModeTile(title: "Review", subtitle: reviewCount == 0 ? "Nothing due" : "\(reviewCount) due", symbol: "arrow.counterclockwise", tint: Theme.tint("coral"), disabled: reviewCount == 0) {
                router.quiz = builder.session(.review)
            }
            ModeTile(title: "Word drill", subtitle: "Glossary terms", symbol: "character.book.closed.fill", tint: Theme.tint("teal")) {
                router.quiz = builder.session(.words(category: nil))
            }
            ModeTile(title: "Quick 5", subtitle: "Anything goes", symbol: "bolt.fill", tint: Theme.tint("amber")) {
                router.quiz = builder.session(.quick)
            }
            ModeTile(title: "Hard mode", subtitle: "Reasoning questions", symbol: "brain", tint: Theme.tint("lime")) {
                let hard = builder.pageItems.filter { $0.difficulty == 3 }.shuffled().prefix(10)
                router.quiz = QuizSession(kind: .quick, title: "Hard mode", items: Array(hard))
            }
        }
    }
}

enum QuizRoute: Hashable { case collection(String) }

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value)
                .font(.serif(.title2, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.rounded(.caption))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
    }
}

struct ModeTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.serif(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 18)
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct MasteryRing: View {
    let value: Double
    let tint: Color
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, value))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))%")
                .font(.rounded(.caption2, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
    }
}

struct CollectionQuizRow: View {
    let collection: Collection
    let items: [QuizItem]
    let mastery: ([QuizItem]) -> Double

    var body: some View {
        let tint = Theme.tint(collection.tint)
        HStack(spacing: 14) {
            Image(systemName: Theme.symbol(collection.symbol))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title).font(.serif(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("\(items.count) questions · \(collection.books.count) books")
                    .font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            MasteryRing(value: mastery(items), tint: tint)
        }
        .padding(14)
        .card(radius: 18)
    }
}

struct CollectionQuizView: View {
    let collection: Collection
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(Router.self) private var router

    var body: some View {
        let builder = QuizBuilder(store: store, state: state)
        let tint = Theme.tint(collection.tint)
        List {
            Section {
                Button { router.quiz = builder.session(.collection(collection.id)) } label: {
                    Label("Mixed quiz from all \(collection.books.count) books", systemImage: "shuffle")
                        .font(.rounded(.headline, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .listRowBackground(Theme.surface)
            }
            Section("Books") {
                ForEach(collection.books) { book in
                    let items = builder.items(forBook: book.id)
                    Button { router.quiz = builder.session(.book(book.id)) } label: {
                        HStack(spacing: 14) {
                            BookCover(book: book, width: 40, showsProgress: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title).font(.serif(.headline)).foregroundStyle(Theme.ink).lineLimit(2)
                                Text("\(items.count) questions").font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            MasteryRing(value: builder.mastery(of: items), tint: tint, size: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(items.isEmpty)
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
