import SwiftData
import Foundation

// MARK: - Enums

enum FoodSource: String, Codable {
    case seed
    case openFoodFacts
    case custom
    case recipe        // Snapshot-Food beim Einloggen eines Rezepts
}

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Frühstück"
    case lunch = "Mittagessen"
    case dinner = "Abendessen"
    case snack = "Snack"
}

enum Sex: String, Codable, CaseIterable {
    case male = "Männlich"
    case female = "Weiblich"
}

/// Harris-Benedict / Mifflin-St-Jeor Aktivitätsmultiplikatoren
enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary        = "Wenig aktiv"
    case lightlyActive    = "Leicht aktiv"
    case moderatelyActive = "Mäßig aktiv"
    case veryActive       = "Sehr aktiv"
    case extraActive      = "Extrem aktiv"

    var multiplier: Double {
        switch self {
        case .sedentary:        1.2
        case .lightlyActive:    1.375
        case .moderatelyActive: 1.55
        case .veryActive:       1.725
        case .extraActive:      1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable {
    case lose     = "Abnehmen"
    case maintain = "Halten"
    case gain     = "Zunehmen"
}

/// Makro-Aufteilung in Prozent — muss in Summe 100 ergeben
struct MacroSplit: Codable {
    var proteinPercent: Double = 30
    var carbsPercent: Double   = 40
    var fatPercent: Double     = 30
}

/// Einheit für die Mengenangabe beim Einloggen (g oder ml; intern immer Gramm)
enum FoodUnit: String, Codable, CaseIterable {
    case grams       = "g"
    case milliliters = "ml"
}

/// Eine benannte Portion (z. B. „1 Scheibe Salami ≈ 15 g")
struct FoodPortion: Codable, Identifiable {
    var id:    UUID   = UUID()
    var name:  String         // z. B. "1 Scheibe"
    var grams: Double         // Gewicht in g
}

// MARK: - SwiftData-Modelle

/// Nährwerte pro 100 g
@Model final class Nutrition {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var salt: Double?
    var saturatedFat: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var iron: Double?
    var calcium: Double?

    init(
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double?       = nil,
        sugar: Double?       = nil,
        salt: Double?        = nil,
        saturatedFat: Double? = nil
    ) {
        self.kcal         = kcal
        self.protein      = protein
        self.carbs        = carbs
        self.fat          = fat
        self.fiber        = fiber
        self.sugar        = sugar
        self.salt         = salt
        self.saturatedFat = saturatedFat
    }
}

/// Ein Lebensmittel aus der Datenbank oder vom Barcode-Scanner
@Model final class Food {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var source: FoodSource
    // deleteRule .cascade: Nutrition wird mit dem Food gelöscht
    @Relationship(deleteRule: .cascade) var nutritionPer100g: Nutrition?
    var defaultServingGrams: Double?
    var createdAt: Date
    var isFavorite: Bool = false
    var searchKeywords: String = ""
    /// Rohzutat (z.B. „Hähnchenbrust roh") — wird im Tagebuch ausgeblendet, im Rezept-Editor sichtbar
    var isIngredient: Bool = false
    /// Portionen als JSON-Data (optional, nil = keine Portionen)
    var storedPortions: Data? = nil
    /// Einheit als Rohstring (nil = g)
    var unitRaw: String? = nil

    init(
        id: UUID                  = UUID(),
        name: String,
        brand: String?            = nil,
        barcode: String?          = nil,
        source: FoodSource,
        nutritionPer100g: Nutrition,
        defaultServingGrams: Double? = nil,
        isIngredient: Bool        = false
    ) {
        self.id                  = id
        self.name                = name
        self.brand               = brand
        self.barcode             = barcode
        self.source              = source
        self.nutritionPer100g    = nutritionPer100g
        self.defaultServingGrams = defaultServingGrams
        self.createdAt           = Date()
        self.isIngredient        = isIngredient
    }

    /// Skaliert die Nährwerte auf eine beliebige Grammzahl
    func nutrition(for grams: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        guard let n = nutritionPer100g else { return (0, 0, 0, 0) }
        let f = grams / 100.0
        return (n.kcal * f, n.protein * f, n.carbs * f, n.fat * f)
    }
}

/// Ein Tagebucheintrag für eine bestimmte Mahlzeit an einem Tag
@Model final class DiaryEntry {
    var id: UUID
    var date: Date
    var meal: MealType
    // Optional: Falls das Food-Objekt gelöscht wird, bleibt der Eintrag erhalten
    var food: Food?
    var grams: Double
    var loggedAt: Date
    /// Freitextnotiz (Feature: Notizen)
    var note: String?
    /// Manuelle Nährwerteingabe ohne Food-Objekt
    var manualName: String?
    var manualKcal: Double?
    var manualProtein: Double?
    var manualCarbs: Double?
    var manualFat: Double?

    // MARK: - Normaler Init (Food-basiert)
    init(
        id: UUID       = UUID(),
        date: Date,
        meal: MealType,
        food: Food,
        grams: Double
    ) {
        self.id       = id
        self.date     = date
        self.meal     = meal
        self.food     = food
        self.grams    = grams
        self.loggedAt = Date()
    }

    // MARK: - Manueller Init (ohne Food)
    init(
        date: Date,
        meal: MealType,
        manualName: String,
        manualKcal: Double,
        manualProtein: Double,
        manualCarbs: Double,
        manualFat: Double
    ) {
        self.id            = UUID()
        self.date          = date
        self.meal          = meal
        self.food          = nil
        self.grams         = 0
        self.loggedAt      = Date()
        self.manualName    = manualName
        self.manualKcal    = manualKcal
        self.manualProtein = manualProtein
        self.manualCarbs   = manualCarbs
        self.manualFat     = manualFat
    }

    // MARK: - Computed

    var isManual: Bool { manualKcal != nil }

    var displayName: String { manualName ?? food?.name ?? "Gelöscht" }

    var kcal: Double {
        if let mk = manualKcal { return mk }
        return food?.nutrition(for: grams).kcal ?? 0
    }
    var protein: Double {
        if let v = manualProtein { return v }
        return food?.nutrition(for: grams).protein ?? 0
    }
    var carbs: Double {
        if let v = manualCarbs { return v }
        return food?.nutrition(for: grams).carbs ?? 0
    }
    var fat: Double {
        if let v = manualFat { return v }
        return food?.nutrition(for: grams).fat ?? 0
    }
}

/// Täglicher Gewichtseintrag
@Model final class WeightEntry {
    var date: Date
    var weightKg: Double

    init(date: Date = Date(), weightKg: Double) {
        self.date     = date
        self.weightKg = weightKg
    }
}

/// Benutzerprofil — genau ein Objekt in der Datenbank
@Model final class UserProfile {
    var sex: Sex
    var birthDate: Date
    var heightCm: Double
    var activityLevel: ActivityLevel
    var goal: Goal
    var weeklyRateKg: Double       // Zielrate in kg/Woche (negativ = abnehmen)
    var currentCalorieTarget: Int  // aktuelles tägliches Kalorienziel
    var currentMacroSplit: MacroSplit
    var lastTargetUpdate: Date     // wann wurde das Ziel zuletzt angepasst
    var waterGoalMl: Double = 2000      // tägliches Wasserziel in ml
    var targetWeightKg: Double? = nil  // Zielgewicht für Prognose (optional)
    // Mikronährstoff-Tagesziele (nil = kein Ziel gesetzt)
    var fiberGoalG:        Double? = nil
    var sugarGoalG:        Double? = nil
    var saturatedFatGoalG: Double? = nil
    var saltGoalG:         Double? = nil

    init(
        sex: Sex,
        birthDate: Date,
        heightCm: Double,
        activityLevel: ActivityLevel,
        goal: Goal,
        weeklyRateKg: Double       = 0.5,
        currentCalorieTarget: Int  = 2000,
        waterGoalMl: Double        = 2000
    ) {
        self.sex                  = sex
        self.birthDate            = birthDate
        self.heightCm             = heightCm
        self.activityLevel        = activityLevel
        self.goal                 = goal
        self.weeklyRateKg         = weeklyRateKg
        self.currentCalorieTarget = currentCalorieTarget
        self.currentMacroSplit    = MacroSplit()
        self.lastTargetUpdate     = Date()
        self.waterGoalMl          = waterGoalMl
    }
}

/// Tägliches Wassertracking — ein Eintrag pro Tag
@Model final class WaterLog {
    var date: Date        // immer startOfDay
    var mlConsumed: Double

    init(date: Date, mlConsumed: Double = 0) {
        self.date       = Calendar.current.startOfDay(for: date)
        self.mlConsumed = mlConsumed
    }
}

/// Ein Rezept mit gramm-basierter Skalierung (Phase 4)
@Model final class Recipe {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var ingredients: [RecipeIngredient]
    var totalCookedWeightGrams: Double   // Gesamtgewicht nach dem Kochen
    var instructions: String?
    var isFavorite: Bool = false

    init(
        id: UUID               = UUID(),
        name: String,
        totalCookedWeightGrams: Double,
        instructions: String?  = nil
    ) {
        self.id                    = id
        self.name                  = name
        self.ingredients           = []
        self.totalCookedWeightGrams = totalCookedWeightGrams
        self.instructions          = instructions
    }
}

/// Eine Zutat innerhalb eines Rezepts
@Model final class RecipeIngredient {
    var food: Food?
    var grams: Double
    var recipe: Recipe?

    init(food: Food, grams: Double) {
        self.food  = food
        self.grams = grams
    }
}

// MARK: - Meal Templates

/// Draft-Eintrag für den Editor (Identifiable, kein @Model)
struct TemplateDraft: Identifiable {
    let id   = UUID()
    let food: Food
    var grams: Double
}

/// Gespeicherte Mahlzeit-Vorlage
@Model final class MealTemplate {
    var id: UUID
    var name: String
    var mealType: MealType
    @Relationship(deleteRule: .cascade) var entries: [TemplateEntry]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, mealType: MealType) {
        self.id        = id
        self.name      = name
        self.mealType  = mealType
        self.entries   = []
        self.createdAt = Date()
    }
}

/// Ein Eintrag innerhalb einer Vorlage
@Model final class TemplateEntry {
    var food: Food?
    var grams: Double
    var template: MealTemplate?

    init(food: Food, grams: Double) {
        self.food  = food
        self.grams = grams
    }
}

// MARK: - Body Measurements

/// Benutzerdefinierter Messungstyp (z.B. "Taille", "cm")
@Model final class BodyMeasurementType {
    var id: UUID
    var name: String
    var unit: String
    var sortOrder: Int
    var groupName: String?   // optionale Gruppe für Kombiniert-Ansicht
    @Relationship(deleteRule: .cascade, inverse: \BodyMeasurement.type)
    var measurements: [BodyMeasurement] = []

    init(id: UUID = UUID(), name: String, unit: String, sortOrder: Int = 0, groupName: String? = nil) {
        self.id        = id
        self.name      = name
        self.unit      = unit
        self.sortOrder = sortOrder
        self.groupName = groupName
    }
}

/// Eine einzelne Messung zu einem Zeitpunkt
@Model final class BodyMeasurement {
    var type: BodyMeasurementType?
    var value: Double
    var date: Date

    init(type: BodyMeasurementType, value: Double, date: Date = Date()) {
        self.type  = type
        self.value = value
        self.date  = date
    }
}

// MARK: - Food-Extensions (computed, außerhalb @Model)

extension Food {
    var portions: [FoodPortion] {
        get {
            guard let data = storedPortions else { return [] }
            return (try? JSONDecoder().decode([FoodPortion].self, from: data)) ?? []
        }
        set {
            storedPortions = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    var unit: FoodUnit {
        get { unitRaw.flatMap(FoodUnit.init(rawValue:)) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }
}

// MARK: - Recipe-Berechnungen

extension Recipe {
    /// Gesamtnährwerte aller Zutaten (roh, vor Skalierung)
    var totalNutrition: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        ingredients.reduce((0.0, 0.0, 0.0, 0.0)) { acc, ing in
            guard let f = ing.food else { return acc }
            let n = f.nutrition(for: ing.grams)
            return (acc.0 + n.kcal, acc.1 + n.protein, acc.2 + n.carbs, acc.3 + n.fat)
        }
    }

    /// Gramm-basierte Skalierung: z.B. 300g von 1200g Bolognese
    func nutrition(for grams: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        guard totalCookedWeightGrams > 0 else { return (0, 0, 0, 0) }
        let total = totalNutrition
        let f = grams / totalCookedWeightGrams
        return (total.kcal * f, total.protein * f, total.carbs * f, total.fat * f)
    }

    /// Kalorien pro 100 g (für Listenansicht)
    var kcalPer100g: Double {
        guard totalCookedWeightGrams > 0 else { return 0 }
        return totalNutrition.kcal / totalCookedWeightGrams * 100.0
    }
}
