import SwiftData
import Foundation

// MARK: - Import-Status

enum ImportStatus {
    case pending
    case done(count: Int)
    case alreadyImported
    case failed(reason: String)
}

// MARK: - JSON-Struktur (spiegelt seed-foods-de.json)

private struct SeedPortion: Codable {
    let name: String
    let grams: Double
}

private struct SeedFoodEntry: Codable {
    let name: String
    let aliases: [String]?
    let category: String?
    let defaultServingGrams: Double?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let sugar: Double?
    let fat: Double
    let saturatedFat: Double?
    let fiber: Double?
    let salt: Double?
    let isIngredient: Bool?
    let portions: [SeedPortion]?

    enum CodingKeys: String, CodingKey {
        case name, aliases, category, kcal, protein, carbs, sugar, fat, fiber, salt, portions
        case defaultServingGrams = "default_serving_grams"
        case saturatedFat        = "saturated_fat"
        case isIngredient        = "is_ingredient"
    }
}

// MARK: - Importer

/// Importiert seed-foods-de.json beim ersten App-Start in SwiftData.
/// v2: Löscht erst alle alten Seed-Foods, dann importiert ~1.200 neue Einträge.
enum SeedFoodImporter {
    private static let importedKey = "seedFoodsImported_v6"

    @MainActor
    static func importIfNeeded(context: ModelContext) async -> ImportStatus {
        if UserDefaults.standard.bool(forKey: importedKey) {
            return .alreadyImported
        }

        // v2-Migration: Alte Seed-Foods löschen (verhindert Duplikate)
        let descriptor = FetchDescriptor<Food>()
        if let allFoods = try? context.fetch(descriptor) {
            for food in allFoods where food.source == .seed {
                context.delete(food)
            }
            try? context.save()
        }

        do {
            let entries = try loadEntries()
            for entry in entries {
                let nutrition = Nutrition(
                    kcal:         entry.kcal,
                    protein:      entry.protein,
                    carbs:        entry.carbs,
                    fat:          entry.fat,
                    fiber:        entry.fiber,
                    sugar:        entry.sugar,
                    salt:         entry.salt,
                    saturatedFat: entry.saturatedFat
                )
                let food = Food(
                    name:                entry.name,
                    source:              .seed,
                    nutritionPer100g:    nutrition,
                    defaultServingGrams: entry.defaultServingGrams,
                    isIngredient:        entry.isIngredient ?? false
                )
                context.insert(food)
                if let seedPortions = entry.portions, !seedPortions.isEmpty {
                    food.portions = seedPortions.map { FoodPortion(name: $0.name, grams: $0.grams) }
                }
                // searchKeywords aus aliases + category aufbauen
                var keywords: [String] = []
                if let aliases = entry.aliases { keywords.append(contentsOf: aliases) }
                if let category = entry.category { keywords.append(category) }
                food.searchKeywords = keywords.joined(separator: " ").lowercased()
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: importedKey)
            print("✅ SeedFoodImporter v2: \(entries.count) Lebensmittel importiert")
            return .done(count: entries.count)
        } catch SeedImportError.fileNotFound {
            print("⚠️  seed-foods-de.json nicht im App-Bundle gefunden")
            return .failed(reason: "seed-foods-de.json fehlt im Bundle")
        } catch {
            print("❌ SeedFoodImporter: \(error)")
            return .failed(reason: error.localizedDescription)
        }
    }

    // MARK: Private

    private static func loadEntries() throws -> [SeedFoodEntry] {
        guard let url = Bundle.main.url(forResource: "seed-foods-de", withExtension: "json") else {
            throw SeedImportError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SeedFoodEntry].self, from: data)
    }
}

enum SeedImportError: Error {
    case fileNotFound
}

// MARK: - Einmalige Korrekturen

extension SeedFoodImporter {
    private static let ingredientFixKey = "seedIngredientFixed_v1"

    /// Setzt isIngredient = true für Seed-Foods deren Name auf " roh" endet.
    /// Läuft nur einmal (UserDefaults-Guard).
    @MainActor
    static func fixRawIngredients(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: ingredientFixKey) else { return }
        let descriptor = FetchDescriptor<Food>()
        guard let foods = try? context.fetch(descriptor) else { return }
        var changed = 0
        for food in foods where food.source == .seed {
            let lower = food.name.lowercased()
            if lower.hasSuffix(" roh") || lower.contains(" roh ") {
                food.isIngredient = true
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        UserDefaults.standard.set(true, forKey: ingredientFixKey)
        print("✅ SeedFoodImporter: \(changed) Rohzutaten als isIngredient markiert")
    }
}
