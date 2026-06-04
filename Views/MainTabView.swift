import SwiftUI
import SwiftData

struct MainTabView: View {
    var body: some View {
        TabView {
            DiaryView()
                .tabItem { Label("Tagebuch", systemImage: "book.fill") }

            SearchView()
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }

            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.fill") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
        .tint(.green)
    }
}
