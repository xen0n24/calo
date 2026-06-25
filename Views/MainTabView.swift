import SwiftUI
import SwiftData

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
        .onChange(of: selectedTab) {
            HapticManager.selection()
        }
    }
}
