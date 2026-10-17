import SwiftUI
import UIKit

/// Full-screen pinch/double-tap zoom for reading the small print on a comic page.
struct ZoomViewer: View {
    let page: Page
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image).ignoresSafeArea()
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
        .task { image = await ImageCache.shared.load(store.url(page.image)) }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 5
        scroll.minimumZoomScale = 1
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.6, height: scroll.bounds.height / 2.6)
                scroll.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}

/// A comic page inside the reader: pinch or double-tap to zoom in place, drag to pan.
/// At normal size it looks like a page card (rounded corners, soft shadow) inside the given insets.
struct PageZoomView: UIViewRepresentable {
    let image: UIImage
    let insets: UIEdgeInsets
    let onSingleTap: () -> Void
    let onZoomChange: (Bool) -> Void
    /// Receives a function returning what's on screen (the zoomed detail, or the whole page).
    var onRegister: ((@escaping () -> (image: UIImage, isDetail: Bool)?) -> Void)? = nil

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        // Not scrollable at normal size, so horizontal swipes keep turning pages.
        scroll.panGestureRecognizer.isEnabled = false

        // The zoomable canvas is the whole page area; the image card sits inside it.
        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(canvas)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.28
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        canvas.addSubview(card)

        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        card.addSubview(imageView)

        let aspect = image.size.width / max(image.size.height, 1)
        let fillWidth = card.widthAnchor.constraint(equalTo: canvas.widthAnchor, constant: -(insets.left + insets.right))
        fillWidth.priority = .defaultHigh
        let fillHeight = card.heightAnchor.constraint(equalTo: canvas.heightAnchor, constant: -(insets.top + insets.bottom))
        fillHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            canvas.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            canvas.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            canvas.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),

            // Largest card with the image's aspect ratio that fits inside the insets, centred in them.
            card.widthAnchor.constraint(equalTo: card.heightAnchor, multiplier: aspect),
            card.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -(insets.left + insets.right)),
            card.heightAnchor.constraint(lessThanOrEqualTo: canvas.heightAnchor, constant: -(insets.top + insets.bottom)),
            fillWidth, fillHeight,
            card.centerXAnchor.constraint(equalTo: canvas.centerXAnchor, constant: (insets.left - insets.right) / 2),
            card.centerYAnchor.constraint(equalTo: canvas.centerYAnchor, constant: (insets.top - insets.bottom) / 2),

            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: card.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        context.coordinator.canvas = canvas
        context.coordinator.card = card
        onRegister? { [weak scroll, weak imageView] in
            guard let scroll, let imageView else { return nil }
            return Self.visibleCrop(of: image, in: imageView, scroll: scroll)
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        #if DEBUG
        if let z = ProcessInfo.processInfo.environment["PANELS_ZOOM"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scroll.setZoomScale(z, animated: false) }
        }
        #endif
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
    }

    /// The part of the page currently on screen, in full resolution.
    static func visibleCrop(of image: UIImage, in imageView: UIView, scroll: UIScrollView) -> (image: UIImage, isDetail: Bool) {
        guard scroll.zoomScale > 1.01, imageView.bounds.width > 0 else { return (image, false) }
        let visible = scroll.convert(scroll.bounds, to: imageView).intersection(imageView.bounds)
        guard !visible.isNull, visible.width > 4, visible.height > 4 else { return (image, false) }
        let factor = image.size.width / imageView.bounds.width
        let rect = CGRect(x: visible.minX * factor, y: visible.minY * factor, width: visible.width * factor, height: visible.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let crop = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
        return (crop, true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: PageZoomView
        weak var canvas: UIView?
        weak var card: UIView?
        private var wasZoomed = false

        init(parent: PageZoomView) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            scrollView.panGestureRecognizer.isEnabled = zoomed
            if zoomed != wasZoomed {
                wasZoomed = zoomed
                parent.onZoomChange(zoomed)
            }
        }

        @objc func singleTapped() { parent.onSingleTap() }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, let canvas else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                // Zoom so the tapped spot of the page fills the screen width at a readable size.
                let point = gesture.location(in: canvas)
                let scale: CGFloat = 2.6
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
