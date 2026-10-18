import SwiftUI

struct QuizSessionView: View {
    let session: QuizSession

    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @AppStorage("advancedMode") private var advanced = false
    @State private var index = 0
    @State private var chosen: Int?
    @State private var results: [String: Bool] = [:]
    @State private var finished = false
    @State private var readerPage: Page?
    @State private var replacement: QuizSession?

    private var item: QuizItem? { session.items.indices.contains(index) ? session.items[index] : nil }
    private let good = Theme.tint("lime")
    private let bad = Theme.tint("coral")

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if session.items.isEmpty {
                ContentUnavailableView("No questions here yet", systemImage: "questionmark.bubble", description: Text("Read a few pages first, then come back."))
            } else if finished {
                QuizSummaryView(session: session, results: results, onRetry: retryMissed, onDone: { dismiss() }, onOpen: { readerPage = $0 })
                    .transition(.opacity)
            } else if let item {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        question(item)
                            .id(item.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    .scrollIndicators(.hidden)
                    footer(item)
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: index)
        .animation(.snappy(duration: 0.25), value: chosen)
        .animation(.easeInOut(duration: 0.3), value: finished)
        .sensoryFeedback(trigger: chosen) { _, new in
            guard let new, let item else { return nil }
            return new == item.correct ? .success : .error
        }
        .fullScreenCover(item: $readerPage) { page in
            if let book = store.book(for: page), let i = book.pages.firstIndex(of: page) {
                ReaderView(book: book, startIndex: i, initialMode: .text)
            }
        }
        .onAppear {
            #if DEBUG
            // Screenshot aid: PANELS_QUIZ_ANSWER=wrong|right answers the first question.
            if let mode = ProcessInfo.processInfo.environment["PANELS_QUIZ_ANSWER"], let item {
                choose(mode == "right" ? item.correct : (item.correct + 1) % item.options.count, item)
            }
            #endif
        }
        .onChange(of: replacement) { _, next in
            // "Second chance" replaces this session in place.
            if let next {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.quiz = next }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleStyle())
            .accessibilityLabel("End quiz")

            HStack(spacing: 4) {
                ForEach(Array(session.items.enumerated()), id: \.offset) { i, it in
                    Capsule()
                        .fill(segmentColor(i, it))
                        .frame(height: 6)
                }
            }
            Text("\(index + 1)/\(session.items.count)")
                .font(.rounded(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func segmentColor(_ i: Int, _ it: QuizItem) -> Color {
        if let r = results[it.id] { return r ? good : bad }
        return i == index ? Theme.ink.opacity(0.55) : Theme.inkTertiary.opacity(0.25)
    }

    private func question(_ item: QuizItem) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                if item.termId != nil {
                    Pill(text: "Word", symbol: "character.book.closed", tint: Theme.tint("teal"))
                } else if let page = item.pageId.flatMap({ store.pages[$0] }) {
                    Pill(text: page.title, symbol: "doc.richtext", tint: Theme.tint(store.book(for: page).flatMap { store.collection(for: $0)?.tint } ?? ""))
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...3, id: \.self) { d in
                        Circle().fill(d <= item.difficulty ? Theme.inkSecondary : Theme.inkTertiary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                .accessibilityLabel("Difficulty \(item.difficulty) of 3")
            }

            Text(item.prompt)
                .font(.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                    OptionButton(
                        letter: item.options.count == 2 ? nil : String(UnicodeScalar(65 + i)!),
                        text: option,
                        state: optionState(i, item),
                        good: good, bad: bad
                    ) { choose(i, item) }
                }
            }

            if let chosen {
                let right = chosen == item.correct
                VStack(alignment: .leading, spacing: 10) {
                    Label(right ? "Correct" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "lightbulb.fill")
                        .font(.rounded(.headline, weight: .bold))
                        .foregroundStyle(right ? good : bad)
                    if !item.explanation.isEmpty {
                        Text(item.explanation)
                            .font(.serif(.body))
                            .foregroundStyle(Theme.ink.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if advanced, let further = item.pageId.flatMap({ store.pages[$0] })?.deeper?.further, !further.isEmpty {
                        Text(further)
                            .font(.serif(.callout))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    if let page = item.pageId.flatMap({ store.pages[$0] }) {
                        Button { readerPage = page } label: {
                            Label("Read “\(page.title)”", systemImage: "book")
                                .font(.rounded(.subheadline, weight: .semibold))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((right ? good : bad).opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 640)
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func footer(_ item: QuizItem) -> some View {
        Button(action: next) {
            Text(index == session.items.count - 1 ? "See results" : "Next question")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FilledButtonStyle(tint: Theme.accent))
        .disabled(chosen == nil)
        .opacity(chosen == nil ? 0.4 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func optionState(_ i: Int, _ item: QuizItem) -> OptionButton.State {
        guard let chosen else { return .idle }
        if i == item.correct { return .correct }
        if i == chosen { return .wrong }
        return .dimmed
    }

    // MARK: Actions

    private func choose(_ i: Int, _ item: QuizItem) {
        guard chosen == nil else { return }
        chosen = i
        let right = i == item.correct
        results[item.id] = right
        state.answer(item, correct: right)
    }

    private func next() {
        if index == session.items.count - 1 {
            state.finish(session)
            finished = true
        } else {
            chosen = nil
            index += 1
        }
    }

    private func retryMissed() {
        let missed = session.items.filter { results[$0.id] == false }.map(\.id)
        replacement = QuizBuilder(store: store, state: state).session(.retry(missed))
    }
}

struct OptionButton: View {
    enum State { case idle, correct, wrong, dimmed }

    let letter: String?
    let text: String
    let state: State
    let good: Color
    let bad: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    switch state {
                    case .correct: Image(systemName: "checkmark")
                    case .wrong: Image(systemName: "xmark")
                    default: Text(letter ?? (text == "True" ? "T" : "F"))
                    }
                }
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(badgeForeground)
                .frame(width: 30, height: 30)
                .background(badgeBackground, in: Circle())

                Text(text)
                    .font(.serif(.body))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border, lineWidth: state == .idle ? 1 : 2))
            .opacity(state == .dimmed ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(state != .idle)
        .accessibilityLabel(text + (state == .correct ? ", correct answer" : state == .wrong ? ", your answer, wrong" : ""))
    }

    private var background: Color {
        switch state {
        case .correct: good.opacity(0.12)
        case .wrong: bad.opacity(0.12)
        default: Theme.surface
        }
    }

    private var border: Color {
        switch state {
        case .correct: good
        case .wrong: bad
        default: Theme.hairline
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .correct: good
        case .wrong: bad
        default: Theme.sunken
        }
    }

    private var badgeForeground: Color {
        switch state {
        case .correct, .wrong: Theme.onTint
        default: Theme.inkSecondary
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct QuizSummaryView: View {
    let session: QuizSession
    let results: [String: Bool]
    let onRetry: () -> Void
    let onDone: () -> Void
    let onOpen: (Page) -> Void

    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @State private var shownScore = 0.0

    var body: some View {
        let correct = results.values.filter { $0 }.count
        let total = session.items.count
        let score = total == 0 ? 0 : Double(correct) / Double(total)
        let tint = score >= 0.8 ? Theme.tint("lime") : score >= 0.5 ? Theme.tint("amber") : Theme.tint("coral")
        let missed = session.items.filter { results[$0.id] == false }

        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: shownScore)
                        .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(correct)/\(total)")
                            .font(.serif(.largeTitle, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                        Text(verdict(score))
                            .font(.rounded(.subheadline, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 190, height: 190)
                .padding(.top, 40)

                HStack(spacing: 12) {
                    StatTile(value: "\(state.streak)", label: "day streak", symbol: "flame.fill", tint: Theme.tint("coral"))
                    StatTile(value: "\(state.xp)", label: "points", symbol: "star.fill", tint: Theme.tint("amber"))
                }

                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To revisit")
                            .font(.serif(.title3, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        ForEach(missed) { item in
                            Button {
                                if let page = item.pageId.flatMap({ store.pages[$0] }) { onOpen(page) }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tint("coral"))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.prompt)
                                            .font(.serif(.subheadline, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                            .multilineTextAlignment(.leading)
                                        Text("Answer: \(item.options[item.correct])")
                                            .font(.serif(.subheadline))
                                            .foregroundStyle(Theme.inkSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    if item.pageId != nil {
                                        Image(systemName: "book").foregroundStyle(Theme.inkTertiary)
                                    }
                                }
                                .padding(14)
                                .card(radius: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 12) {
                    if !missed.isEmpty {
                        Button(action: onRetry) {
                            Label("Retry the \(missed.count) I missed", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle(tint: Theme.accent))
                    }
                    Button(action: onDone) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(tint: Theme.accent, secondary: true))
                }
            }
            .frame(maxWidth: 640)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { shownScore = max(score, 0.001) } }
        .sensoryFeedback(.success, trigger: shownScore)
    }

    private func verdict(_ score: Double) -> String {
        switch score {
        case 1: "Perfect"
        case 0.8...: "Great work"
        case 0.5...: "Getting there"
        default: "Keep reading"
        }
    }
}
