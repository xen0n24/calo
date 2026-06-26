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

/// Unsichtbarer UIViewController, der einen Pan-Gesture-Recognizer auf der
/// nativen UITabBar installiert – ohne deren Aussehen zu verändern.
private struct TabBarHapticInstaller: UIViewControllerRepresentable {
    let itemCount: Int

    func makeCoordinator() -> HapticGestureHandler {
        HapticGestureHandler(itemCount: itemCount)
    }

    func makeUIViewController(context: Context) -> InstallerVC {
        InstallerVC(handler: context.coordinator)
    }

    func updateUIViewController(_ vc: InstallerVC, context: Context) {}
}

// MARK: Gesture handler

private final class HapticGestureHandler: NSObject, UIGestureRecognizerDelegate {
    let itemCount: Int
    private var lastIdx = -1

    init(itemCount: Int) {
        self.itemCount = itemCount
    }

    @objc func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        switch gr.state {
        case .changed:
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

    // Gleichzeitige Erkennung mit nativer Tab-Bar-Geste erlauben
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
}

// MARK: Installer view controller

private final class InstallerVC: UIViewController {
    private let handler: HapticGestureHandler
    private var installed = false

    init(handler: HapticGestureHandler) {
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !installed else { return }
        installGesture()
    }

    private func installGesture() {
        // Responder-Chain nach oben laufen bis UITabBarController gefunden
        var responder: UIResponder? = self
        while let r = responder {
            if let tbc = r as? UITabBarController {
                let pan = UIPanGestureRecognizer(
                    target: handler,
                    action: #selector(HapticGestureHandler.handlePan(_:))
                )
                pan.delegate                = handler
                pan.cancelsTouchesInView    = false
                pan.delaysTouchesBegan      = false
                pan.delaysTouchesEnded      = false
                tbc.tabBar.addGestureRecognizer(pan)
                installed = true
                return
            }
            responder = r.next
        }
    }
}
