import SwiftUI
import UIKit

/// UIPageViewController with the page-curl transition, so turning pages feels like a real book.
struct PageCurlView: UIViewControllerRepresentable {
    let count: Int
    @Binding var index: Int
    let mode: ReaderMode
    /// Off while a comic page is zoomed, so dragging pans the page instead of turning it.
    var pagingEnabled = true
    let makePage: (Int, ReaderMode) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        controller.view.backgroundColor = .clear
        controller.setViewControllers([context.coordinator.controller(for: index)], direction: .forward, animated: false)
        context.coordinator.shownIndex = index
        context.coordinator.shownMode = mode
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller.gestureRecognizers.forEach { $0.isEnabled = pagingEnabled }
        if coordinator.shownMode != mode {
            // Rebuild the current page in the new mode without turning.
            coordinator.shownMode = mode
            coordinator.cache.removeAll()
            controller.setViewControllers([coordinator.controller(for: index)], direction: .forward, animated: false)
            coordinator.shownIndex = index
        } else if coordinator.shownIndex != index, !coordinator.isTransitioning {
            let direction: UIPageViewController.NavigationDirection = index > coordinator.shownIndex ? .forward : .reverse
            coordinator.shownIndex = index
            controller.setViewControllers([coordinator.controller(for: index)], direction: direction, animated: true)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        var shownIndex = 0
        var shownMode = ReaderMode.comic
        var isTransitioning = false
        var cache: [Int: UIViewController] = [:]

        init(_ parent: PageCurlView) { self.parent = parent }

        func controller(for index: Int) -> UIViewController {
            if let cached = cache[index] { return cached }
            let host = UIHostingController(rootView: parent.makePage(index, parent.mode))
            host.view.backgroundColor = UIColor(parent.mode == .text ? Theme.paper : Theme.background)
            host.view.tag = index
            // Keep memory bounded: only neighbours of the current page stay cached.
            cache = cache.filter { abs($0.key - index) <= 2 }
            cache[index] = host
            return host
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            let i = vc.view.tag
            return i > 0 ? controller(for: i - 1) : nil
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            let i = vc.view.tag
            return i < parent.count - 1 ? controller(for: i + 1) : nil
        }

        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pending: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            guard completed, let current = pvc.viewControllers?.first else { return }
            shownIndex = current.view.tag
            if parent.index != shownIndex { parent.index = shownIndex }
        }
    }
}
