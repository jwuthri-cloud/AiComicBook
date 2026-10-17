import SwiftUI

/// Something played full screen from the Practice section.
enum Game: Identifiable, Equatable {
    case flashcards(title: String, termIds: [String])
    case match
    case speed
    case zoom

    var id: String {
        switch self {
        case .flashcards(let title, let ids): "cards:\(title):\(ids.count)"
        case .match: "match"
        case .speed: "speed"
        case .zoom: "zoom"
        }
    }
}

struct GameHost: View {
    let game: Game
    @Environment(ContentStore.self) private var store

    var body: some View {
        switch game {
        case .flashcards(let title, let ids):
            FlashcardsView(title: title, terms: ids.compactMap { store.terms[$0] })
        case .match: MatchGameView()
        case .speed: SpeedRoundView()
        case .zoom: ZoomGuessView()
        }
    }
}

/// Shared end-of-game card.
private struct GameOver: View {
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    let isRecord: Bool
    let again: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: isRecord ? "trophy.fill" : symbol)
                .font(.system(size: 64))
                .foregroundStyle(isRecord ? Theme.tint("amber") : tint)
                .symbolEffect(.bounce, value: isRecord)
            if isRecord {
                Text("NEW BEST").font(.rounded(.caption, weight: .heavy)).tracking(2).foregroundStyle(Theme.tint("amber"))
            }
            Text(headline)
                .font(.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.rounded(.headline))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: again) { Label("Play again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                .buttonStyle(FilledButtonStyle(tint: tint))
            Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
        }
        .padding(24)
    }
}

// MARK: - Match

/// Pair five words with their meanings, three rounds, against the clock.
struct MatchGameView: View {
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("best.match") private var best = 0.0

    private static let rounds = 3
    private static let pairs = 5

    @State private var round = 0
    @State private var terms: [Term] = []
    @State private var definitions: [Term] = []
    @State private var selectedTerm: String?
    @State private var selectedDef: String?
    @State private var matched: Set<String> = []
    @State private var wrongIds: Set<String> = []
    @State private var slipped: Set<String> = []
    @State private var mistakes = 0
    @State private var start = Date.now
    @State private var finishedTime: Double?
    @State private var shake = 0
    @State private var success = 0
    @State private var isRecord = false

    private let tint = Theme.tint("teal")

    var body: some View {
        NavigationStack {
            Group {
                if let time = finishedTime {
                    GameOver(symbol: "square.grid.2x2.fill", tint: tint, headline: String(format: "%.1f s", time),
                             detail: "\(Self.rounds * Self.pairs) pairs · \(mistakes) \(mistakes == 1 ? "slip" : "slips") (+3 s each)",
                             isRecord: isRecord, again: newGame, done: { dismiss() })
                } else {
                    board
                }
            }
            .background(Theme.background)
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if finishedTime == nil {
                    ToolbarItem(placement: .principal) {
                        TimelineView(.periodic(from: .now, by: 0.1)) { context in
                            Text(String(format: "%.1f s", context.date.timeIntervalSince(start) + Double(mistakes * 3)))
                                .font(.rounded(.headline, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            .sensoryFeedback(.error, trigger: shake)
            .sensoryFeedback(.success, trigger: success)
        }
        .onAppear(perform: newGame)
    }

    private var board: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Round \(round + 1) of \(Self.rounds)")
                Spacer()
                if best > 0 { Text(String(format: "Best %.1f s", best)) }
            }
            .font(.rounded(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(terms) { term in
                        tile(term.term, id: term.id, selected: selectedTerm == term.id, serif: true) {
                            selectedTerm = selectedTerm == term.id ? nil : term.id
                            check()
                        }
                    }
                }
                .frame(width: 128)
                VStack(spacing: 10) {
                    ForEach(definitions) { term in
                        tile(term.short, id: term.id, selected: selectedDef == term.id, serif: false) {
                            selectedDef = selectedDef == term.id ? nil : term.id
                            check()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Tap a word, then its meaning.")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(16)
    }

    private func tile(_ text: String, id: String, selected: Bool, serif: Bool, action: @escaping () -> Void) -> some View {
        let done = matched.contains(id)
        let wrong = wrongIds.contains(id)
        return Button(action: action) {
            Text(text)
                .font(serif ? .serif(.subheadline, weight: .semibold) : .rounded(.caption))
                .foregroundStyle(done ? Theme.tint("lime") : Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(serif ? 3 : 5)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                    done ? Theme.tint("lime").opacity(0.12) : (wrong ? Theme.tint("coral").opacity(0.16) : (selected ? tint.opacity(0.16) : Theme.surface)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? tint : Theme.hairline, lineWidth: selected ? 2 : 1)
                )
                .modifier(Shake(amount: wrong ? 1 : 0))
        }
        .buttonStyle(.plain)
        .disabled(done)
        .opacity(done ? 0.45 : 1)
        .animation(.snappy(duration: 0.25), value: done)
        .animation(.snappy(duration: 0.15), value: selected)
    }

    private func check() {
        guard let t = selectedTerm, let d = selectedDef else { return }
        selectedTerm = nil
        selectedDef = nil
        if t == d {
            matched.insert(t)
            success += 1
            state.mark("term:\(t):name", correct: !slipped.contains(t), points: 5)
            if terms.allSatisfy({ matched.contains($0.id) }) { nextRound() }
        } else {
            mistakes += 1
            shake += 1
            slipped.insert(t)
            withAnimation(.linear(duration: 0.35)) { wrongIds = [t, d] }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wrongIds = [] }
        }
    }

    private func nextRound() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if round + 1 < Self.rounds {
                round += 1
                deal()
            } else {
                let time = Date.now.timeIntervalSince(start) + Double(mistakes * 3)
                isRecord = best == 0 || time < best
                if isRecord { best = time }
                state.award(max(10, 60 - mistakes * 5))
                state.practiced()
                withAnimation { finishedTime = time }
            }
        }
    }

    private func newGame() {
        round = 0
        mistakes = 0
        slipped = []
        finishedTime = nil
        isRecord = false
        start = .now
        deal()
    }

    private func deal() {
        // One topic per round keeps the meanings close enough to make you think.
        let byCategory = Dictionary(grouping: store.glossary, by: \.category).filter { $0.value.count >= Self.pairs }
        let pool = byCategory.randomElement()?.value ?? store.glossary
        let chosen = PracticeDecks.weighted(pool, state: state, count: Self.pairs)
        withAnimation(.snappy) {
            matched = []
            terms = chosen.shuffled()
            definitions = chosen.shuffled()
        }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(amount * .pi * 4), y: 0))
    }
}

// MARK: - Speed round

/// 60 seconds: is this the right meaning? Streaks multiply the score.
struct SpeedRoundView: View {
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("best.speed") private var best = 0

    private static let duration = 60.0

    @State private var term: Term?
    @State private var shown: Term?
    @State private var score = 0
    @State private var streak = 0
    @State private var answered = 0
    @State private var correctCount = 0
    @State private var start: Date?
    @State private var over = false
    @State private var flash: Bool?
    @State private var isRecord = false
    @State private var ticker = 0

    private let tint = Theme.tint("amber")

    var body: some View {
        NavigationStack {
            Group {
                if over {
                    GameOver(symbol: "bolt.fill", tint: tint, headline: "\(score) points",
                             detail: "\(correctCount) of \(answered) right" + (answered > 0 ? " · \(Int(Double(correctCount) / Double(answered) * 100))%" : ""),
                             isRecord: isRecord, again: begin, done: { dismiss() })
                } else if start == nil {
                    intro
                } else {
                    playing
                }
            }
            .background(Theme.background)
            .navigationTitle("Speed round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sensoryFeedback(trigger: ticker) { _, _ in flash == true ? .success : .error }
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bolt.circle.fill").font(.system(size: 72)).foregroundStyle(tint)
            Text("60 seconds").font(.serif(.largeTitle, weight: .bold)).foregroundStyle(Theme.ink)
            Text("A word and a meaning appear. Is it the right meaning? Answer as many as you can — streaks multiply your points.")
                .font(.serif(.body))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            if best > 0 { Pill(text: "Best: \(best)", symbol: "trophy.fill", tint: tint) }
            Spacer()
            Button(action: begin) { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(FilledButtonStyle(tint: tint))
        }
        .padding(24)
    }

    private var playing: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let left = max(0, Self.duration - context.date.timeIntervalSince(start ?? .now))
                VStack(spacing: 6) {
                    ProgressView(value: left, total: Self.duration).tint(left < 10 ? Theme.tint("coral") : tint)
                    HStack {
                        Text("\(Int(left.rounded(.up))) s").monospacedDigit()
                        Spacer()
                        if streak >= 3 { Text("×\(multiplier) streak").foregroundStyle(tint) }
                        Spacer()
                        Text("\(score) pts").monospacedDigit()
                    }
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                }
                .onChange(of: left <= 0) { _, ended in if ended { finish() } }
            }
            Spacer(minLength: 0)
            if let term, let shown {
                VStack(alignment: .leading, spacing: 16) {
                    Pill(text: term.category, tint: Theme.categoryTint(term.category))
                    Text(term.term)
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text("means…").font(.rounded(.subheadline)).foregroundStyle(Theme.inkTertiary)
                    Text(shown.short)
                        .font(.serif(.title3))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(flashColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.hairline))
                .id(term.id)
                .transition(.push(from: .trailing))
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                answerButton("Wrong", symbol: "xmark", color: Theme.tint("coral"), value: false)
                answerButton("Right", symbol: "checkmark", color: Theme.tint("lime"), value: true)
            }
        }
        .padding(20)
    }

    private var flashColor: Color {
        switch flash {
        case true?: Theme.tint("lime").opacity(0.18)
        case false?: Theme.tint("coral").opacity(0.18)
        default: Theme.surface
        }
    }

    private var multiplier: Int { min(4, 1 + streak / 3) }

    private func answerButton(_ title: String, symbol: String, color: Color, value: Bool) -> some View {
        Button { answer(value) } label: {
            Label(title, systemImage: symbol)
                .font(.rounded(.title3, weight: .bold))
                .foregroundStyle(Theme.onTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func begin() {
        score = 0
        streak = 0
        answered = 0
        correctCount = 0
        over = false
        isRecord = false
        start = .now
        deal()
    }

    private func deal() {
        guard let next = store.glossary.randomElement() else { return }
        let honest = Bool.random()
        var shownTerm = next
        if !honest {
            let siblings = store.glossary.filter { $0.category == next.category && $0.id != next.id && $0.short != next.short }
            shownTerm = siblings.randomElement() ?? store.glossary.first { $0.id != next.id } ?? next
        }
        withAnimation(.snappy(duration: 0.25)) {
            term = next
            shown = shownTerm
            flash = nil
        }
    }

    private func answer(_ saysRight: Bool) {
        guard !over, let term, let shown else { return }
        let isRight = (term.id == shown.id) == saysRight
        answered += 1
        if isRight {
            correctCount += 1
            streak += 1
            score += 10 * multiplier
        } else {
            streak = 0
            state.mark("term:\(term.id):meaning", correct: false)
        }
        flash = isRight
        ticker += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { if !over { deal() } }
    }

    private func finish() {
        guard !over else { return }
        isRecord = score > best
        if isRecord { best = score }
        state.award(score / 5)
        state.practiced()
        withAnimation { over = true }
    }
}

// MARK: - Zoom guess

/// A zoomed-in detail of a comic page: which page is it? Each wrong guess zooms out (3, 2, then 1 point).
struct ZoomGuessView: View {
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("best.zoom") private var best = 0

    private static let rounds = 8
    private static let zooms: [CGFloat] = [3.4, 2.2, 1.35, 1]

    @State private var round = 0
    @State private var page: Page?
    @State private var options: [Page] = []
    @State private var eliminated: Set<String> = []
    @State private var level = 0
    @State private var anchor = UnitPoint.center
    @State private var solved = false
    @State private var score = 0
    @State private var over = false
    @State private var isRecord = false
    @State private var feedback = 0

    private let tint = Theme.tint("violet")

    var body: some View {
        NavigationStack {
            Group {
                if over {
                    GameOver(symbol: "magnifyingglass", tint: tint, headline: "\(score) of \(Self.rounds * 3)",
                             detail: score >= Self.rounds * 2 ? "Sharp eyes!" : "Every guess teaches you the pages a little better.",
                             isRecord: isRecord, again: newGame, done: { dismiss() })
                } else if let page {
                    playing(page)
                }
            }
            .background(Theme.background)
            .navigationTitle("Zoom guess")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Text("\(score) pts").font(.rounded(.headline, weight: .bold).monospacedDigit()).foregroundStyle(tint)
                }
            }
            .sensoryFeedback(.selection, trigger: feedback)
        }
        .onAppear(perform: newGame)
    }

    private func playing(_ page: Page) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Round \(round + 1) of \(Self.rounds)")
                Spacer()
                Text(solved ? "" : "Worth \(max(1, 3 - level)) \(3 - level == 1 ? "point" : "points")")
            }
            .font(.rounded(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)

            GeometryReader { geo in
                ContentImage(path: page.image, contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(solved ? 1 : Self.zooms[min(level, Self.zooms.count - 1)], anchor: anchor)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: level)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: solved)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
            .frame(maxHeight: .infinity)

            Text(solved ? (store.book(for: page)?.title ?? "") : "Which page is this detail from?")
                .font(.rounded(.footnote, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            VStack(spacing: 8) {
                ForEach(options) { option in
                    let isAnswer = option.id == page.id
                    let gone = eliminated.contains(option.id)
                    Button { guess(option) } label: {
                        HStack {
                            Text(option.title)
                                .font(.serif(.subheadline, weight: .semibold))
                                .foregroundStyle(gone ? Theme.inkTertiary : Theme.ink)
                                .strikethrough(gone)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if solved && isAnswer { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.tint("lime")) }
                            if gone { Image(systemName: "xmark").foregroundStyle(Theme.tint("coral")) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(solved && isAnswer ? Theme.tint("lime").opacity(0.15) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .disabled(gone || solved)
                }
            }

            if solved {
                HStack(spacing: 10) {
                    Button { open(page) } label: { Label("Read it", systemImage: "book").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
                    Button(action: nextRound) {
                        Label(round + 1 < Self.rounds ? "Next" : "Finish", systemImage: "arrow.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(tint: tint))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
    }

    private func guess(_ option: Page) {
        guard let page, !solved else { return }
        feedback += 1
        if option.id == page.id {
            score += max(1, 3 - level)
            withAnimation(.snappy) { solved = true }
        } else {
            eliminated.insert(option.id)
            level += 1
            if eliminated.count >= options.count - 1 { withAnimation(.snappy) { solved = true } }
        }
    }

    private func nextRound() {
        if round + 1 < Self.rounds {
            round += 1
            deal()
        } else {
            isRecord = score > best
            if isRecord { best = score }
            state.award(score * 3)
            state.practiced()
            withAnimation { over = true }
        }
    }

    private func newGame() {
        round = 0
        score = 0
        over = false
        isRecord = false
        deal()
    }

    private func deal() {
        // Pages with real pictures (not cover-like title pages), answers from the same collection.
        let pool = store.allBooks.flatMap(\.pages).filter { $0.hasText }
        guard let pick = pool.randomElement(), let book = store.book(for: pick) else { return }
        let siblings = store.collection(for: book).map { $0.books.flatMap(\.pages) } ?? book.pages
        let distractors = siblings.filter { $0.id != pick.id && $0.title != pick.title }.shuffled().prefix(3)
        withAnimation(.snappy) {
            page = pick
            options = ([pick] + distractors).shuffled()
            eliminated = []
            level = 0
            solved = false
            // Away from the top, where the page title is printed.
            anchor = UnitPoint(x: .random(in: 0.2...0.8), y: .random(in: 0.38...0.85))
        }
    }

    private func open(_ page: Page) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.read(page: page, in: store, mode: .comic) }
    }
}
