import SwiftUI
import SwiftData

/// Root-View: leitet zu Onboarding oder Hauptapp weiter.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .task {
            // Seed-Daten einmalig im Hintergrund importieren
            _ = await SeedFoodImporter.importIfNeeded(context: modelContext)
            // Einmalig: isIngredient-Flag für Rohzutaten korrigieren
            SeedFoodImporter.fixRawIngredients(context: modelContext)
        }
    }
}
