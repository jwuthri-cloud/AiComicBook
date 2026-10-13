import SwiftUI
import UIKit

/// Decodes bundled images off the main thread and keeps them in memory.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() { cache.countLimit = 160 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let raw = UIImage(contentsOfFile: url.path) else { return nil }
            return raw.preparingForDisplay() ?? raw
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct ContentImage: View {
    @Environment(ContentStore.self) private var store
    let path: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        let url = store.url(path)
        Group {
            if let image = image ?? ImageCache.shared.cached(url) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Theme.sunken)
                    .overlay(ProgressView().tint(Theme.inkTertiary))
            }
        }
        .task(id: path) { image = await ImageCache.shared.load(url) }
    }
}
