import SwiftData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup Codable Structs

struct BackupV1: Codable {
    var version:              Int                         = 1
    var exportedAt:           Date                        = Date()
    var foods:                [FoodBackup]                = []
    var recipes:              [RecipeBackup]              = []
    var diaryEntries:         [DiaryEntryBackup]          = []
    var weightEntries:        [WeightEntryBackup]         = []
    var waterLogs:            [WaterLogBackup]            = []
    var profile:              ProfileBackup?              = nil
    var templates:            [MealTemplateBackup]        = []
    var bodyMeasurementTypes: [BodyMeasurementTypeBackup] = []
    var bodyMeasurements:     [BodyMeasurementBackup]     = []
}

struct FoodBackup: Codable {
    var id:                  UUID
    var name:                String
    var brand:               String?
    var barcode:             String?
    var source:              FoodSource
    var kcal:                Double
    var protein:             Double
    var carbs:               Double
    var fat:                 Double
    var fiber:               Double?
    var sugar:               Double?
    var salt:                Double?
    var saturatedFat:        Double?
    var defaultServingGrams: Double?
    var isFavorite:          Bool
    var searchKeywords:      String
    var isIngredient:        Bool
    var portions:            [FoodPortion]
    var unit:                FoodUnit
}

struct RecipeBackup: Codable {
    var id:                     UUID
    var name:                   String
    var totalCookedWeightGrams: Double
    var instructions:           String?
    var isFavorite:             Bool
    var ingredients:            [IngredientBackup]
}

struct IngredientBackup: Codable {
    var foodId:   UUID
    var foodName: String
    var grams:    Double
}

struct DiaryEntryBackup: Codable {
    var id:            UUID
    var date:          Date
    var meal:          MealType
    var foodId:        UUID?
    var foodName:      String?
    var grams:         Double
    var loggedAt:      Date
    var note:          String?
    var manualName:    String?
    var manualKcal:    Double?
    var manualProtein: Double?
    var manualCarbs:   Double?
    var manualFat:     Double?
}

struct WeightEntryBackup: Codable {
    var date:     Date
    var weightKg: Double
}

struct WaterLogBackup: Codable {
    var date:       Date
    var mlConsumed: Double
}

struct ProfileBackup: Codable {
    var sex:                  Sex
    var birthDate:            Date
    var heightCm:             Double
    var activityLevel:        ActivityLevel
    var goal:                 Goal
    var weeklyRateKg:         Double
    var currentCalorieTarget: Int
    var currentMacroSplit:    MacroSplit
    var waterGoalMl:          Double
    var targetWeightKg:       Double?
    var fiberGoalG:           Double?
    var sugarGoalG:           Double?
    var saturatedFatGoalG:    Double?
    var saltGoalG:            Double?
}

struct MealTemplateBackup: Codable {
    var id:       UUID
    var name:     String
    var mealType: MealType
    var entries:  [TemplateEntryBackup]
}

struct TemplateEntryBackup: Codable {
    var foodId:   UUID
    var foodName: String
    var grams:    Double
}

struct BodyMeasurementTypeBackup: Codable {
    var id:        UUID
    var name:      String
    var unit:      String
    var sortOrder: Int
}

struct BodyMeasurementBackup: Codable {
    var typeId:   UUID
    var typeName: String
    var value:    Double
    var date:     Date
}

// MARK: - Import Result

struct BackupImportResult {
    var foodsImported:         Int  = 0
    var recipesImported:       Int  = 0
    var diaryEntriesImported:  Int  = 0
    var weightEntriesImported: Int  = 0
    var waterLogsImported:     Int  = 0
    var templatesImported:     Int  = 0
    var measurementsImported:  Int  = 0
    var profileRestored:       Bool = false

    var summary: String {
        var parts: [String] = []
        if foodsImported         > 0 { parts.append("\(foodsImported) Lebensmittel") }
        if recipesImported       > 0 { parts.append("\(recipesImported) Rezepte") }
        if diaryEntriesImported  > 0 { parts.append("\(diaryEntriesImported) Tagebucheinträge") }
        if weightEntriesImported > 0 { parts.append("\(weightEntriesImported) Gewichtseinträge") }
        if waterLogsImported     > 0 { parts.append("\(waterLogsImported) Wassereinträge") }
        if templatesImported     > 0 { parts.append("\(templatesImported) Vorlagen") }
        if measurementsImported  > 0 { parts.append("\(measurementsImported) Körpermaße") }
        if profileRestored             { parts.append("Profil") }
        return parts.isEmpty
            ? "Nichts Neues importiert (alles bereits vorhanden)."
            : "Importiert: \(parts.joined(separator: ", "))."
    }
}

// MARK: - BackupManager

enum BackupManager {

    // MARK: - Export

    static func export(context: ModelContext) throws -> URL {
        var backup = BackupV1()

        // Foods (alle, inkl. Seed – für vollständige Diary-Referenzen)
        if let foods = try? context.fetch(FetchDescriptor<Food>()) {
            backup.foods = foods.compactMap { f -> FoodBackup? in
                guard let n = f.nutritionPer100g else { return nil }
                return FoodBackup(
                    id:                  f.id,
                    name:                f.name,
                    brand:               f.brand,
                    barcode:             f.barcode,
                    source:              f.source,
                    kcal:                n.kcal,
                    protein:             n.protein,
                    carbs:               n.carbs,
                    fat:                 n.fat,
                    fiber:               n.fiber,
                    sugar:               n.sugar,
                    salt:                n.salt,
                    saturatedFat:        n.saturatedFat,
                    defaultServingGrams: f.defaultServingGrams,
                    isFavorite:          f.isFavorite,
                    searchKeywords:      f.searchKeywords,
                    isIngredient:        f.isIngredient,
                    portions:            f.portions,
                    unit:                f.unit
                )
            }
        }

        // Recipes
        if let recipes = try? context.fetch(FetchDescriptor<Recipe>()) {
            backup.recipes = recipes.map { r in
                RecipeBackup(
                    id:                     r.id,
                    name:                   r.name,
                    totalCookedWeightGrams: r.totalCookedWeightGrams,
                    instructions:           r.instructions,
                    isFavorite:             r.isFavorite,
                    ingredients:            r.ingredients.compactMap { ing -> IngredientBackup? in
                        guard let f = ing.food else { return nil }
                        return IngredientBackup(foodId: f.id, foodName: f.name, grams: ing.grams)
                    }
                )
            }
        }

        // Diary entries
        if let entries = try? context.fetch(FetchDescriptor<DiaryEntry>()) {
            backup.diaryEntries = entries.map { e in
                DiaryEntryBackup(
                    id:            e.id,
                    date:          e.date,
                    meal:          e.meal,
                    foodId:        e.food?.id,
                    foodName:      e.food?.name,
                    grams:         e.grams,
                    loggedAt:      e.loggedAt,
                    note:          e.note,
                    manualName:    e.manualName,
                    manualKcal:    e.manualKcal,
                    manualProtein: e.manualProtein,
                    manualCarbs:   e.manualCarbs,
                    manualFat:     e.manualFat
                )
            }
        }

        // Weight entries
        if let weights = try? context.fetch(FetchDescriptor<WeightEntry>()) {
            backup.weightEntries = weights.map {
                WeightEntryBackup(date: $0.date, weightKg: $0.weightKg)
            }
        }

        // Water logs
        if let logs = try? context.fetch(FetchDescriptor<WaterLog>()) {
            backup.waterLogs = logs.map {
                WaterLogBackup(date: $0.date, mlConsumed: $0.mlConsumed)
            }
        }

        // Profile
        if let p = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            backup.profile = ProfileBackup(
                sex:                  p.sex,
                birthDate:            p.birthDate,
                heightCm:             p.heightCm,
                activityLevel:        p.activityLevel,
                goal:                 p.goal,
                weeklyRateKg:         p.weeklyRateKg,
                currentCalorieTarget: p.currentCalorieTarget,
                currentMacroSplit:    p.currentMacroSplit,
                waterGoalMl:          p.waterGoalMl,
                targetWeightKg:       p.targetWeightKg,
                fiberGoalG:           p.fiberGoalG,
                sugarGoalG:           p.sugarGoalG,
                saturatedFatGoalG:    p.saturatedFatGoalG,
                saltGoalG:            p.saltGoalG
            )
        }

        // Templates
        if let templates = try? context.fetch(FetchDescriptor<MealTemplate>()) {
            backup.templates = templates.map { t in
                MealTemplateBackup(
                    id:       t.id,
                    name:     t.name,
                    mealType: t.mealType,
                    entries:  t.entries.compactMap { e -> TemplateEntryBackup? in
                        guard let f = e.food else { return nil }
                        return TemplateEntryBackup(foodId: f.id, foodName: f.name, grams: e.grams)
                    }
                )
            }
        }

        // Body measurement types
        if let types = try? context.fetch(FetchDescriptor<BodyMeasurementType>()) {
            backup.bodyMeasurementTypes = types.map {
                BodyMeasurementTypeBackup(id: $0.id, name: $0.name, unit: $0.unit, sortOrder: $0.sortOrder)
            }
        }

        // Body measurements
        if let measurements = try? context.fetch(FetchDescriptor<BodyMeasurement>()) {
            backup.bodyMeasurements = measurements.compactMap { m -> BodyMeasurementBackup? in
                guard let t = m.type else { return nil }
                return BodyMeasurementBackup(typeId: t.id, typeName: t.name, value: m.value, date: m.date)
            }
        }

        // JSON encodieren
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Calo-Backup-\(fmt.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    static func importBackup(from url: URL, context: ModelContext) throws -> BackupImportResult {
        var result = BackupImportResult()

        let data    = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup  = try decoder.decode(BackupV1.self, from: data)

        // Vorhandene Foods per UUID ermitteln
        let existingFoods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        var foodByUUID: [UUID: Food] = [:]
        for f in existingFoods { foodByUUID[f.id] = f }

        // Foods importieren (nur neue)
        for fb in backup.foods {
            guard foodByUUID[fb.id] == nil else { continue }
            let n = Nutrition(
                kcal:         fb.kcal,   protein:      fb.protein,
                carbs:        fb.carbs,  fat:          fb.fat,
                fiber:        fb.fiber,  sugar:        fb.sugar,
                salt:         fb.salt,   saturatedFat: fb.saturatedFat
            )
            context.insert(n)
            let food = Food(
                id:                  fb.id,
                name:                fb.name,
                brand:               fb.brand,
                barcode:             fb.barcode,
                source:              fb.source,
                nutritionPer100g:    n,
                defaultServingGrams: fb.defaultServingGrams,
                isIngredient:        fb.isIngredient
            )
            food.isFavorite     = fb.isFavorite
            food.searchKeywords = fb.searchKeywords
            food.portions       = fb.portions
            food.unit           = fb.unit
            context.insert(food)
            foodByUUID[fb.id]   = food
            result.foodsImported += 1
        }

        // Recipes (nur neue per UUID)
        let existingRecipeIDs = Set((try? context.fetch(FetchDescriptor<Recipe>()))?.map(\.id) ?? [])
        for rb in backup.recipes {
            guard !existingRecipeIDs.contains(rb.id) else { continue }
            let recipe = Recipe(
                id:                     rb.id,
                name:                   rb.name,
                totalCookedWeightGrams: rb.totalCookedWeightGrams,
                instructions:           rb.instructions
            )
            recipe.isFavorite = rb.isFavorite
            context.insert(recipe)
            for ib in rb.ingredients {
                guard let food = foodByUUID[ib.foodId] else { continue }
                let ing = RecipeIngredient(food: food, grams: ib.grams)
                context.insert(ing)
                ing.recipe = recipe
                recipe.ingredients.append(ing)
            }
            result.recipesImported += 1
        }

        // Diary entries (nur neue per UUID)
        let existingEntryIDs = Set((try? context.fetch(FetchDescriptor<DiaryEntry>()))?.map(\.id) ?? [])
        for eb in backup.diaryEntries {
            guard !existingEntryIDs.contains(eb.id) else { continue }
            let entry: DiaryEntry
            if let mn = eb.manualName, let mk = eb.manualKcal {
                entry = DiaryEntry(
                    date:          eb.date,
                    meal:          eb.meal,
                    manualName:    mn,
                    manualKcal:    mk,
                    manualProtein: eb.manualProtein ?? 0,
                    manualCarbs:   eb.manualCarbs   ?? 0,
                    manualFat:     eb.manualFat      ?? 0
                )
            } else {
                guard let fid = eb.foodId, let food = foodByUUID[fid] else { continue }
                entry = DiaryEntry(date: eb.date, meal: eb.meal, food: food, grams: eb.grams)
            }
            entry.note = eb.note
            context.insert(entry)
            result.diaryEntriesImported += 1
        }

        // Weight entries (pro Tag nur einmal)
        let existingWeightDays = Set(
            (try? context.fetch(FetchDescriptor<WeightEntry>()))?
                .map { Calendar.current.startOfDay(for: $0.date) } ?? []
        )
        for wb in backup.weightEntries {
            let day = Calendar.current.startOfDay(for: wb.date)
            guard !existingWeightDays.contains(day) else { continue }
            context.insert(WeightEntry(date: wb.date, weightKg: wb.weightKg))
            result.weightEntriesImported += 1
        }

        // Water logs (pro Tag nur einmal)
        let existingWaterDays = Set(
            (try? context.fetch(FetchDescriptor<WaterLog>()))?.map(\.date) ?? []
        )
        for wl in backup.waterLogs {
            let day = Calendar.current.startOfDay(for: wl.date)
            guard !existingWaterDays.contains(day) else { continue }
            context.insert(WaterLog(date: wl.date, mlConsumed: wl.mlConsumed))
            result.waterLogsImported += 1
        }

        // Profil wiederherstellen (vorhandenes updaten, kein neues anlegen)
        if let pb = backup.profile,
           let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            existing.sex                  = pb.sex
            existing.birthDate            = pb.birthDate
            existing.heightCm             = pb.heightCm
            existing.activityLevel        = pb.activityLevel
            existing.goal                 = pb.goal
            existing.weeklyRateKg         = pb.weeklyRateKg
            existing.currentCalorieTarget = pb.currentCalorieTarget
            existing.currentMacroSplit    = pb.currentMacroSplit
            existing.waterGoalMl          = pb.waterGoalMl
            existing.targetWeightKg       = pb.targetWeightKg
            existing.fiberGoalG           = pb.fiberGoalG
            existing.sugarGoalG           = pb.sugarGoalG
            existing.saturatedFatGoalG    = pb.saturatedFatGoalG
            existing.saltGoalG            = pb.saltGoalG
            result.profileRestored = true
        }

        // Templates (nur neue per UUID)
        let existingTemplateIDs = Set(
            (try? context.fetch(FetchDescriptor<MealTemplate>()))?.map(\.id) ?? []
        )
        for tb in backup.templates {
            guard !existingTemplateIDs.contains(tb.id) else { continue }
            let t = MealTemplate(id: tb.id, name: tb.name, mealType: tb.mealType)
            context.insert(t)
            for eb in tb.entries {
                guard let food = foodByUUID[eb.foodId] else { continue }
                let te = TemplateEntry(food: food, grams: eb.grams)
                context.insert(te)
                te.template = t
                t.entries.append(te)
            }
            result.templatesImported += 1
        }

        // Body measurement types (Merge per UUID)
        var typeByUUID: [UUID: BodyMeasurementType] = [:]
        for existing in (try? context.fetch(FetchDescriptor<BodyMeasurementType>())) ?? [] {
            typeByUUID[existing.id] = existing
        }
        for tb in backup.bodyMeasurementTypes {
            if typeByUUID[tb.id] == nil {
                let t = BodyMeasurementType(
                    id: tb.id, name: tb.name, unit: tb.unit, sortOrder: tb.sortOrder
                )
                context.insert(t)
                typeByUUID[tb.id] = t
            }
        }

        // Body measurements
        for mb in backup.bodyMeasurements {
            guard let type = typeByUUID[mb.typeId] else { continue }
            let m = BodyMeasurement(type: type, value: mb.value, date: mb.date)
            context.insert(m)
            result.measurementsImported += 1
        }

        try context.save()
        return result
    }
}

// MARK: - ActivityView (UIKit Share Sheet)

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - ShareURL (Identifiable Wrapper)

struct ShareURL: Identifiable {
    let id  = UUID()
    let url: URL
}
