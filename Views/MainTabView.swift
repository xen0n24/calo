import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DiaryView()
                .tabItem { Label("Tagebuch", systemImage: "book.fill") }
                .tag(0)

            SearchView()
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
                .tag(1)

            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.fill") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
                .tag(3)
        }
        .tint(.green)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .background(TabBarHapticInstaller(itemCount: 4))
    }
}

// MARK: - UIKit Haptic Installer

private struct TabBarHapticInstaller: UIViewRepresentable {
    let itemCount: Int

    func makeCoordinator() -> HapticGestureHandler {
        HapticGestureHandler(itemCount: itemCount)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        scheduleInstall(from: view, handler: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func scheduleInstall(from view: UIView, handler: HapticGestureHandler, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !handler.installed else { return }
            if let window = view.window, let tabBar = findTabBar(in: window) {
                let pan = UIPanGestureRecognizer(
                    target: handler,
                    action: #selector(HapticGestureHandler.handlePan(_:))
                )
                pan.delegate             = handler
                pan.cancelsTouchesInView = false
                pan.delaysTouchesBegan   = false
                pan.delaysTouchesEnded   = false
                tabBar.addGestureRecognizer(pan)
                handler.installed = true
            } else if attempt < 10 {
                scheduleInstall(from: view, handler: handler, attempt: attempt + 1)
            }
        }
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Gesture handler

final class HapticGestureHandler: NSObject, UIGestureRecognizerDelegate {
    let itemCount: Int
    var installed = false
    private var lastIdx = -1

    init(itemCount: Int) { self.itemCount = itemCount }

    @objc func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        switch gr.state {
        case .began, .changed:
            let x   = gr.location(in: view).x
            let w   = view.bounds.width / CGFloat(itemCount)
            let idx = min(itemCount - 1, max(0, Int(x / w)))
            if idx != lastIdx {
                lastIdx = idx
                HapticManager.selection()
            }
        case .ended, .cancelled, .failed:
            lastIdx = -1
        default:
            break
        }
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
}
