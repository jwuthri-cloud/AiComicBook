import AVKit
import SwiftUI

struct WatchView: View {
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watch")
                            .font(.serif(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("Short narrated explainers, \(formatDuration(store.videoBooks.map(\.totalDuration).reduce(0, +))) in total. Sound plays even in silent mode.")
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.horizontal, 20)

                    ForEach(store.videoBooks) { book in
                        VideoShelf(book: book)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .withRoutes()
        }
    }
}

struct VideoShelf: View {
    let book: Book
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let tint = Theme.tint(store.collection(for: book)?.tint ?? "")
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.serif(.title3, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(book.videoPages.count) clips · \(formatDuration(book.totalDuration))")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button { router.watch(book) } label: {
                    Label("Play all", systemImage: "play.fill")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.onTint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(book.videoPages) { page in
                        Button { router.watch(book, from: page) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomLeading) {
                                    ContentImage(path: page.poster ?? page.thumb)
                                        .frame(width: 236, height: 133)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                        Text(formatDuration(page.duration ?? 10))
                                    }
                                    .font(.rounded(.caption, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                }
                                .frame(width: 236, height: 133)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                Text("\(page.number). \(page.title)")
                                    .font(.serif(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .frame(width: 236, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// Plays a book's clips back to back with the system player (AirPlay, Picture in Picture, scrubbing).
struct BookPlayerView: View {
    let book: Book
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var store
    @State private var title = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            QueuePlayer(urls: book.videoPages.dropFirst(startIndex).compactMap { $0.video.map(store.url) },
                        titles: book.videoPages.dropFirst(startIndex).map(\.title),
                        onTitle: { title = $0 },
                        onFinished: { dismiss() })
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(title).font(.serif(.subheadline, weight: .semibold)).foregroundStyle(.white)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
        }
        .background(.black)
    }
}

struct QueuePlayer: UIViewControllerRepresentable {
    let urls: [URL]
    let titles: [String]
    let onTitle: (String) -> Void
    let onFinished: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let items = urls.map { AVPlayerItem(url: $0) }
        let player = AVQueuePlayer(items: items)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        context.coordinator.observe(player: player, items: items)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        coordinator.observation = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator {
        let parent: QueuePlayer
        var observation: NSKeyValueObservation?
        var items: [AVPlayerItem] = []

        init(parent: QueuePlayer) { self.parent = parent }

        func observe(player: AVQueuePlayer, items: [AVPlayerItem]) {
            self.items = items
            observation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let item = player.currentItem, let i = self.items.firstIndex(of: item) {
                        self.parent.onTitle(self.parent.titles[i])
                    } else if player.currentItem == nil, !self.items.isEmpty {
                        self.parent.onFinished()
                    }
                }
            }
        }
    }
}
