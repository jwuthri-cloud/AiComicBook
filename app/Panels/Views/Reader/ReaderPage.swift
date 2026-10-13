import AVKit
import SwiftUI

/// One page of the reader in the chosen mode.
struct ReaderPage: View {
    let page: Page
    let book: Book
    let mode: ReaderMode
    let tint: Color
    let onTerm: (Term) -> Void
    let onZoom: (Page) -> Void
    let onToggleChrome: () -> Void
    let onChrome: (Bool) -> Void
    let onZoomChange: (Bool) -> Void
    let onWatchBook: (Page) -> Void

    var body: some View {
        switch mode {
        case .comic:
            ComicPageView(page: page, onToggleChrome: onToggleChrome, onZoomChange: onZoomChange)
        case .text:
            TextPageView(page: page, book: book, tint: tint, onTerm: onTerm, onChrome: onChrome)
        case .video:
            VideoPageView(page: page, book: book, tint: tint, onWatchBook: onWatchBook)
        }
    }
}

// MARK: - Comic

struct ComicPageView: View {
    let page: Page
    let onToggleChrome: () -> Void
    let onZoomChange: (Bool) -> Void

    @Environment(ContentStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    PageZoomView(
                        image: image,
                        insets: UIEdgeInsets(top: geo.safeAreaInsets.top + 54, left: 14, bottom: geo.safeAreaInsets.bottom + 92, right: 14),
                        onSingleTap: onToggleChrome,
                        onZoomChange: onZoomChange
                    )
                } else {
                    ProgressView().tint(Theme.inkTertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .accessibilityLabel("Comic page: \(page.title). Pinch or double-tap to zoom.")
        }
        .ignoresSafeArea()
        .background(Theme.background)
        .task(id: page.id) { image = await ImageCache.shared.load(store.url(page.image)) }
    }
}

// MARK: - Text

struct TextPageView: View {
    let page: Page
    let book: Book
    let tint: Color
    let onTerm: (Term) -> Void
    let onChrome: (Bool) -> Void

    @Environment(ContentStore.self) private var store
    @AppStorage("textScale") private var storedScale = 1.0
    @GestureState private var pinch: CGFloat = 1

    /// Reading size; pinching previews live and is remembered when the fingers lift.
    private var textScale: Double { Self.clamp(storedScale * pinch) }
    static func clamp(_ v: Double) -> Double { min(1.6, max(0.85, v)) }

    var body: some View {
        let linked = linkedPanels()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("PAGE \(page.number) · \(book.title.uppercased())")
                    .font(.rounded(.caption2, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.bottom, 12)

                Text(page.title)
                    .font(.system(size: 34 * textScale, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !page.subtitle.isEmpty {
                    Text(page.subtitle)
                        .font(.system(size: 20 * textScale, design: .serif).italic())
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Ornament(tint: tint).padding(.vertical, 22)

                if !page.wordKey.isEmpty {
                    WordKeyBox(text: page.wordKey, tint: tint, scale: textScale)
                        .padding(.bottom, 24)
                }

                if page.panels.isEmpty {
                    Text(page.summary.isEmpty ? "This page is best read as a comic." : page.summary)
                        .font(.system(size: 18 * textScale, design: .serif))
                        .foregroundStyle(Theme.inkSecondary)
                }

                ForEach(Array(page.panels.enumerated()), id: \.offset) { i, panel in
                    PanelText(panel: panel, body: linked[i], tint: tint, scale: textScale)
                        .padding(.bottom, 26)
                }

                if !page.footer.isEmpty {
                    PullQuote(text: page.footer, tint: tint, scale: textScale)
                        .padding(.vertical, 8)
                }

                let terms = termsOnPage(linked)
                if !terms.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Words on this page")
                            .font(.rounded(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        FlowLayout(spacing: 8) {
                            ForEach(terms) { term in
                                Button { onTerm(term) } label: {
                                    Text(term.aka.first(where: { $0.count <= 6 }) ?? term.term)
                                        .font(.rounded(.subheadline, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Theme.surface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.hairline))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 28)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 70)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper)
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in storedScale = Self.clamp(storedScale * value.magnification) }
        )
        // Reading: tuck the bars away while scrolling down, bring them back when scrolling up.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
            if new > old + 6, new > 40 { onChrome(false) } else if new < old - 6 || new < 20 { onChrome(true) }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "panels-term", let id = url.host(), let term = store.terms[id] {
                onTerm(term)
                return .handled
            }
            return .systemAction
        })
    }

    /// Panel bodies with each glossary term linked the first time it appears on the page.
    private func linkedPanels() -> [AttributedString] {
        var seen = Set<String>()
        let skip = store.termsToSkip(in: book)
        return page.panels.map { panel in
            var attributed = AttributedString(panel.body)
            for match in store.termMatcher.matches(in: panel.body, seen: &seen, excluding: skip) {
                guard let lower = AttributedString.Index(match.range.lowerBound, within: attributed),
                      let upper = AttributedString.Index(match.range.upperBound, within: attributed) else { continue }
                let range = lower..<upper
                attributed[range].link = URL(string: "panels-term://\(match.termId)")
                attributed[range].underlineStyle = Text.LineStyle(pattern: .dot, color: tint.opacity(0.7))
                attributed[range].foregroundColor = tint
            }
            return attributed
        }
    }

    private func termsOnPage(_ linked: [AttributedString]) -> [Term] {
        var ids: [String] = []
        for text in linked {
            for run in text.runs {
                if let url = run.link, url.scheme == "panels-term", let id = url.host(), !ids.contains(id) { ids.append(id) }
            }
        }
        return ids.compactMap { store.terms[$0] }
    }
}

private struct PanelText: View {
    let panel: Panel
    let body_: AttributedString
    let tint: Color
    let scale: Double

    init(panel: Panel, body: AttributedString, tint: Color, scale: Double) {
        self.panel = panel
        self.body_ = body
        self.tint = tint
        self.scale = scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(panel.number)")
                    .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(width: 28 * scale, height: 28 * scale)
                    .background(tint.opacity(0.14), in: Circle())
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 * scale }
                Text(panel.heading)
                    .font(.system(size: 21 * scale, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !panel.body.isEmpty {
                Text(body_)
                    .font(.system(size: 18 * scale, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.88))
                    .lineSpacing(6 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let code = panel.code, !code.isEmpty {
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(size: 14 * scale, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .textSelection(.enabled)
                }
                .scrollIndicators(.hidden)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct WordKeyBox: View {
    let text: String
    let tint: Color
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Word key", systemImage: "key.fill")
                .font(.rounded(.caption, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15 * scale, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.2)))
    }
}

private struct PullQuote: View {
    let text: String
    let tint: Color
    let scale: Double

    var body: some View {
        VStack(spacing: 14) {
            Rectangle().fill(tint.opacity(0.5)).frame(width: 36, height: 2)
            Text(text)
                .font(.system(size: 21 * scale, weight: .medium, design: .serif).italic())
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(tint.opacity(0.5)).frame(width: 36, height: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

struct Ornament: View {
    let tint: Color
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(tint.opacity(0.7))
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

// MARK: - Video

struct VideoPageView: View {
    let page: Page
    let book: Book
    let tint: Color
    let onWatchBook: (Page) -> Void

    @Environment(ContentStore.self) private var store
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let video = page.video {
                    ZStack {
                        if let player {
                            VideoPlayer(player: player)
                        } else if let poster = page.poster {
                            ContentImage(path: poster)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    .onAppear {
                        let p = AVPlayer(url: store.url(video))
                        player = p
                        p.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CLIP \(page.number) OF \(book.videoPages.count)")
                            .font(.rounded(.caption2, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(tint)
                        Text(page.title)
                            .font(.serif(.title2, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if !page.subtitle.isEmpty {
                            Text(page.subtitle)
                                .font(.serif(.body).italic())
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }

                    Button { onWatchBook(page) } label: {
                        Label("Play the whole book · \(formatDuration(book.totalDuration))", systemImage: "play.rectangle.on.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))

                    if !page.summary.isEmpty {
                        Text(page.summary)
                            .font(.serif(.body))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(4)
                    }
                } else {
                    ContentUnavailableView("No video for this page", systemImage: "video.slash", description: Text("Switch to Comic or Text to read it."))
                        .padding(.top, 120)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 20)
            .padding(.top, 76)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }
}

// MARK: - Layout helper

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
