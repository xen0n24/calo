import SwiftUI
import SwiftData

@main
struct CaloApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try Self.makeContainer()
        } catch {
            // Store beschädigt – löschen und neu anlegen (Daten gehen verloren)
            Self.deleteStore()
            do {
                container = try Self.makeContainer()
            } catch {
                fatalError("SwiftData konnte nicht gestartet werden: \(error)")
            }
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Food.self, Nutrition.self, DiaryEntry.self, WeightEntry.self,
            UserProfile.self, Recipe.self, RecipeIngredient.self, WaterLog.self,
            MealTemplate.self, TemplateEntry.self,
            BodyMeasurementType.self, BodyMeasurement.self
        ])
        let config = ModelConfiguration("CaloStore", schema: schema)
        return try ModelContainer(for: schema, configurations: config)
    }

    private static func deleteStore() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory,
                                    in: .userDomainMask).first else { return }
        for suffix in [".store", ".store-wal", ".store-shm"] {
            try? fm.removeItem(at: support.appendingPathComponent("CaloStore\(suffix)"))
        }
    }

    @State private var appTheme = AppTheme()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(appTheme)
        }
    }
}
