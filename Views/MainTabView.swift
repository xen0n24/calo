import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                DiaryView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                SearchView()
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                StatsView()
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
                ProfileView()
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 49)
            }

            SlideHapticTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct SlideHapticTabBar: View {
    @Binding var selectedTab: Int
    @Environment(AppTheme.self) private var theme

    private let items: [(String, String)] = [
        ("book.fill",      "Tagebuch"),
        ("magnifyingglass","Suche"),
        ("chart.bar.fill", "Statistik"),
        ("person.fill",    "Profil"),
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        guard selectedTab != i else { return }
                        selectedTab = i
                        HapticManager.selection()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: items[i].0)
                                .font(.system(size: 21))
                            Text(items[i].1)
                                .font(.caption2)
                        }
                        .foregroundStyle(selectedTab == i ? theme.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        let w = geo.size.width / CGFloat(items.count)
                        let idx = min(items.count - 1, max(0, Int(value.location.x / w)))
                        guard idx != selectedTab else { return }
                        selectedTab = idx
                        HapticManager.selection()
                    }
            )
        }
        .frame(height: 49)
        .background(
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) { Divider() }
    }
}
