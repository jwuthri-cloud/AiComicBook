import SwiftUI

/// A comic page dressed as a physical book: spine shading, page edges and a soft drop shadow.
struct BookCover: View {
    let book: Book
    var width: CGFloat = 132
    var showsProgress = true

    @Environment(LibraryState.self) private var library

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Page block peeking out on the right edge.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.paper)
                .overlay(alignment: .trailing) {
                    VStack(spacing: 1.2) {
                        ForEach(0..<36, id: \.self) { _ in
                            Rectangle().fill(Theme.hairline).frame(height: 0.6)
                        }
                    }
                    .frame(width: 4)
                    .padding(.vertical, 4)
                }
                .offset(x: 4, y: 2)

            ContentImage(path: book.cover)
                .frame(width: width, height: height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 7, topTrailingRadius: 7, style: .continuous))
                .overlay(alignment: .leading) {
                    // Spine: a crease and a soft highlight.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.38), location: 0),
                            .init(color: .white.opacity(0.16), location: 0.05),
                            .init(color: .black.opacity(0.12), location: 0.08),
                            .init(color: .clear, location: 0.16),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if book.hasVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(6)
                    }
                }
        }
        .frame(width: width + 4, height: height, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 10, x: 3, y: 8)
        .overlay(alignment: .bottom) {
            if showsProgress {
                let progress = library.progress(of: book)
                if progress > 0 {
                    ProgressBar(value: progress)
                        .frame(width: width - 20, height: 4)
                        .padding(.bottom, 8)
                        .offset(x: -2)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * value))
            }
        }
    }
}

/// Cover + title + subtitle, used in shelves.
struct ShelfBook: View {
    let book: Book
    var width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookCover(book: book, width: width)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text("\(book.pages.count) \(book.pages.count == 1 ? "page" : "pages")")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}
