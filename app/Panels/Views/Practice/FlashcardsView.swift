import SwiftUI

/// Glossary flashcards: tap to flip, swipe right if you knew it, left to see it again.
/// Answers feed the same spaced-repetition boxes as the quiz's word questions.
struct FlashcardsView: View {
    let title: String
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var deck: [Term]
    @State private var position = 0
    @State private var flipped = false
    @State private var drag: CGSize = .zero
    @State private var known: [Term] = []
    @State private var missed: [Term] = []
    @State private var requeued: [String: Int] = [:]
    @State private var feedback = 0

    init(title: String, terms: [Term]) {
        self.title = title
        _deck = State(initialValue: terms)
    }

    private var finished: Bool { position >= deck.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if finished {
                    summary
                } else {
                    progressBar.padding(.horizontal, 24).padding(.top, 8)
                    Spacer(minLength: 12)
                    cardStack
                    Spacer(minLength: 12)
                    controls.padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { finishAndClose() } }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        }
    }

    // MARK: Cards

    private var progressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(position), total: Double(max(deck.count, 1)))
                .tint(Theme.accent)
            HStack {
                Label("\(known.count)", systemImage: "checkmark").foregroundStyle(Theme.tint("lime"))
                Spacer()
                Text("\(min(position + 1, deck.count)) of \(deck.count)").foregroundStyle(Theme.inkSecondary)
                Spacer()
                Label("\(missed.count)", systemImage: "arrow.counterclockwise").foregroundStyle(Theme.tint("coral"))
            }
            .font(.rounded(.caption, weight: .semibold).monospacedDigit())
        }
    }

    private var cardStack: some View {
        ZStack {
            // The next card peeks out from behind.
            if position + 1 < deck.count {
                FlashcardFace(term: deck[position + 1], showBack: false)
                    .scaleEffect(0.94)
                    .offset(y: 14)
                    .opacity(0.6)
            }
            let term = deck[position]
            ZStack {
                FlashcardFace(term: term, showBack: false)
                    .opacity(flipped ? 0 : 1)
                FlashcardFace(term: term, showBack: true)
                    .rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                    .opacity(flipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)
            .overlay(alignment: .topLeading) { stamp("KNOW IT", tint: Theme.tint("lime")).opacity(Double(max(0, drag.width / 120))) }
            .overlay(alignment: .topTrailing) { stamp("AGAIN", tint: Theme.tint("coral")).opacity(Double(max(0, -drag.width / 120))) }
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width / 18)))
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if value.translation.width > 110 || value.predictedEndTranslation.width > 260 {
                            swipe(knewIt: true)
                        } else if value.translation.width < -110 || value.predictedEndTranslation.width < -260 {
                            swipe(knewIt: false)
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() }
                feedback += 1
            }
            .id(term.id)
            .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .identity))
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to flip. Use the buttons below to answer.")
    }

    private func stamp(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.rounded(.title3, weight: .heavy))
            .tracking(2)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 3))
            .rotationEffect(.degrees(text == "AGAIN" ? 12 : -12))
            .padding(24)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            roundButton("xmark", tint: Theme.tint("coral"), label: "Again") { swipe(knewIt: false) }
            roundButton("arrow.trianglehead.2.clockwise.rotate.90", tint: Theme.inkSecondary, label: "Flip", small: true) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() }
            }
            roundButton("checkmark", tint: Theme.tint("lime"), label: "I knew it") { swipe(knewIt: true) }
        }
    }

    private func roundButton(_ symbol: String, tint: Color, label: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 18 : 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: small ? 52 : 66, height: small ? 52 : 66)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func swipe(knewIt: Bool) {
        guard !finished else { return }
        let term = deck[position]
        state.mark("term:\(term.id):meaning", correct: knewIt, points: 5)
        if knewIt {
            if !known.contains(term) && !missed.contains(term) { known.append(term) }
        } else {
            if !missed.contains(term) { missed.append(term) }
            // Missed cards come back at the end of the deck (twice at most).
            if requeued[term.id, default: 0] < 2 {
                requeued[term.id, default: 0] += 1
                deck.append(term)
            }
        }
        feedback += 1
        withAnimation(.easeIn(duration: 0.22)) { drag = CGSize(width: knewIt ? 600 : -600, height: drag.height + 40) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            flipped = false
            drag = .zero
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { position += 1 }
            if position >= deck.count { state.practiced() }
        }
    }

    // MARK: Summary

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: missed.isEmpty ? "star.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(missed.isEmpty ? Theme.tint("amber") : Theme.tint("lime"))
                    .padding(.top, 30)
                Text(missed.isEmpty ? "You knew them all!" : "Deck done")
                    .font(.serif(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(known.count) known first time · \(missed.count) to practise")
                    .font(.rounded(.headline))
                    .foregroundStyle(Theme.inkSecondary)
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Coming back in your reviews").font(.serif(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        ForEach(missed) { TermRow(term: $0) }
                    }
                    .padding(16)
                    .card(radius: 18)
                    Button {
                        deck = missed.shuffled()
                        known = []
                        missed = []
                        requeued = [:]
                        position = 0
                    } label: {
                        Label("Go again with these \(missed.count)", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(tint: Theme.tint("coral")))
                }
                Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(FilledButtonStyle(tint: Theme.accent, secondary: !missed.isEmpty))
            }
            .padding(24)
        }
    }

    private func finishAndClose() {
        if position > 0 { state.practiced() }
        dismiss()
    }
}

/// One side of a flashcard.
struct FlashcardFace: View {
    let term: Term
    let showBack: Bool

    var body: some View {
        let tint = Theme.categoryTint(term.category)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Pill(text: term.category, tint: tint)
                Spacer()
                Image(systemName: showBack ? "text.book.closed" : "questionmark.circle")
                    .foregroundStyle(tint.opacity(0.7))
            }
            Spacer(minLength: 0)
            if showBack {
                Text(term.term)
                    .font(.serif(.headline, weight: .semibold))
                    .foregroundStyle(tint)
                Text(term.short)
                    .font(.serif(.title3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(term.definition)
                    .font(.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
                    .lineLimit(9)
                    .minimumScaleFactor(0.85)
            } else {
                Text(term.term)
                    .font(.serif(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
                if !term.aka.isEmpty {
                    Text(term.aka.joined(separator: " · "))
                        .font(.rounded(.headline, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text("Do you know what it means?")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: 520)
        .frame(height: 440)
        .background(
            LinearGradient(colors: [tint.opacity(showBack ? 0.06 : 0.14), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(tint.opacity(0.22)))
        .shadow(color: .black.opacity(0.10), radius: 20, y: 10)
    }
}

/// Choose a flashcard deck.
struct FlashcardDecksView: View {
    @Environment(ContentStore.self) private var store
    @Environment(QuizState.self) private var state
    @Environment(LibraryState.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let categories = Array(Set(store.glossary.map(\.category))).sorted()
        List {
            Section {
                deckRow("Smart deck", subtitle: "Words due for review, then new ones", symbol: "sparkles", tint: Theme.accent) {
                    router.game = .flashcards(title: "Smart deck", termIds: PracticeDecks.smart(store: store, state: state).map(\.id))
                }
                let fromReading = PracticeDecks.fromReading(store: store, library: library)
                if fromReading.count >= 5 {
                    deckRow("From your reading", subtitle: "\(fromReading.count) words on pages you've read", symbol: "book.fill", tint: Theme.tint("violet")) {
                        router.game = .flashcards(title: "From your reading", termIds: fromReading.shuffled().prefix(20).map(\.id))
                    }
                }
            }
            Section("By topic") {
                ForEach(categories, id: \.self) { c in
                    let terms = store.glossary.filter { $0.category == c }
                    let mastered = terms.filter { state.isMastered("term:\($0.id):meaning") }.count
                    deckRow(c, subtitle: "\(terms.count) words · \(mastered) mastered", symbol: "character.book.closed.fill", tint: Theme.categoryTint(c)) {
                        router.game = .flashcards(title: c, termIds: PracticeDecks.weighted(terms, state: state, count: 20).map(\.id))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deckRow(_ title: String, subtitle: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.serif(.headline)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.rounded(.caption)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "play.fill").foregroundStyle(tint)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
    }
}

/// Which words to practise.
enum PracticeDecks {
    /// Due or missed words first, then unseen, then the rest.
    static func weighted(_ terms: [Term], state: QuizState, count: Int) -> [Term] {
        func weight(_ t: Term) -> Double {
            let id = "term:\(t.id):meaning"
            guard let r = state.record(id) else { return 2.5 }
            return r.box == 0 ? 5 : (state.isDue(id) ? 3 : 0.4)
        }
        return terms
            .map { ($0, -log(Double.random(in: 0.0001...1)) / weight($0)) }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map(\.0)
    }

    static func smart(store: ContentStore, state: QuizState) -> [Term] {
        weighted(store.glossary, state: state, count: 20)
    }

    static func fromReading(store: ContentStore, library: LibraryState) -> [Term] {
        store.glossary.filter { term in term.pages.contains { id in store.pages[id].map(library.isRead) ?? false } }
    }
}
