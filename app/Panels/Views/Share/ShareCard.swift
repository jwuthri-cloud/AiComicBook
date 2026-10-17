import SwiftUI
import UIKit

/// An image ready for the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String
}

/// Turns a comic crop or a panel of text into a tidy card image for Messages, Instagram, notes…
enum ShareCard {
    @MainActor
    static func comic(_ image: UIImage, page: Page, book: Book, collection: Collection?, isDetail: Bool) -> ShareItem {
        let tint = Theme.tint(collection?.tint ?? "")
        let card = CardFrame(tint: tint, page: page, book: book) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        } caption: {
            if !page.footer.isEmpty && !isDetail {
                Text(page.footer)
                    .font(.system(size: 17, weight: .medium, design: .serif).italic())
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        return ShareItem(image: render(card), text: "\(page.title) — from “\(book.title)” in Panels")
    }

    @MainActor
    static func text(_ panel: Panel, page: Page, book: Book, collection: Collection?) -> ShareItem {
        let tint = Theme.tint(collection?.tint ?? "")
        let card = CardFrame(tint: tint, page: page, book: book) {
            VStack(alignment: .leading, spacing: 12) {
                Text(panel.heading)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(panel.body)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.88))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let code = panel.code, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 4).padding(.vertical, 18) }
        } caption: {
            EmptyView()
        }
        let body = panel.body.count > 400 ? String(panel.body.prefix(400)) + "…" : panel.body
        return ShareItem(image: render(card), text: "\(panel.heading)\n\n\(body)\n\n— “\(page.title)”, \(book.title) (Panels)")
    }

    @MainActor
    private static func render(_ view: some View) -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 390).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

private struct CardFrame<Content: View, Caption: View>: View {
    let tint: Color
    let page: Page
    let book: Book
    @ViewBuilder let content: Content
    @ViewBuilder let caption: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PAGE \(page.number) · \(book.title.uppercased())")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(page.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            content
            caption
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                Text("Panels")
                Spacer()
                Text("Learn it in pictures")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.inkTertiary)
        }
        .padding(22)
        .background(Theme.paper)
    }
}

/// UIKit share sheet (lets the card be saved to Photos, sent, copied…).
struct ActivityView: UIViewControllerRepresentable {
    let item: ShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.image, item.text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Lets the reader grab exactly what's visible in a zoomed comic page.
final class ZoomRegistry {
    private var providers: [String: () -> (image: UIImage, isDetail: Bool)?] = [:]

    func register(_ pageId: String, _ provider: @escaping () -> (image: UIImage, isDetail: Bool)?) {
        providers[pageId] = provider
    }

    func visible(_ pageId: String) -> (image: UIImage, isDetail: Bool)? { providers[pageId]?() }
}
