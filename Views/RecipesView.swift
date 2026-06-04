import SwiftUI
import SwiftData

// MARK: - RecipesView (eingebettet in SearchView)

struct RecipesView: View {
    @Environment(AppTheme.self)  private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var showEditor        = false
    @State private var editingRecipe: Recipe? = nil
    @State private var detailRecipe: Recipe?  = nil

    var body: some View {
        Group {
            if recipes.isEmpty {
                emptyState
            } else {
                recipeList
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            RecipeEditorView()
        }
        .sheet(item: $editingRecipe) { r in
            RecipeEditorView(recipe: r)
        }
        .sheet(item: $detailRecipe) { r in
            RecipeDetailSheet(recipe: r)
        }
    }

    // MARK: - Liste

    private var recipeList: some View {
        List {
            ForEach(recipes) { recipe in
                Button { detailRecipe = recipe } label: {
                    RecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button {
                        recipe.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            recipe.isFavorite ? "Entfernen" : "Favorit",
                            systemImage: recipe.isFavorite ? "heart.slash.fill" : "heart.fill"
                        )
                    }
                    .tint(recipe.isFavorite ? .gray : .pink)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(recipe) } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    Button { editingRecipe = recipe } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
    }

    // MARK: - Leer-Zustand

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Rezepte", systemImage: "fork.knife")
        } description: {
            Text("Erstelle dein erstes Rezept mit dem + Button.")
        } actions: {
            Button("Rezept erstellen") { showEditor = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
    }

    private func delete(_ recipe: Recipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
    }
}

// MARK: - RecipeRow

struct RecipeRow: View {
    @Environment(AppTheme.self) private var theme

    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name).font(.headline)
                Text("\(recipe.ingredients.count) Zutaten · \(Int(recipe.totalCookedWeightGrams)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(recipe.totalNutrition.kcal)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text("gesamt")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - RecipeDetailSheet

struct RecipeDetailSheet: View {
    let recipe: Recipe

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @State private var grams: Double     = 100
    @State private var selectedMeal: MealType = .breakfast
    @State private var selectedDate: Date     = .now

    private var portion: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        recipe.nutrition(for: grams)
    }

    var body: some View {
        NavigationStack {
            List {
                // Kalorien-Highlight
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(Int(portion.kcal))")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent)
                            Text("kcal für \(Int(grams)) g")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Menge
                Section("Menge") {
                    NumericStepperView(
                        value: $grams,
                        range: 1...max(1, recipe.totalCookedWeightGrams),
                        step: 10,
                        unit: "g"
                    )
                    Button("Ganze Portion (\(Int(recipe.totalCookedWeightGrams)) g)") {
                        grams = recipe.totalCookedWeightGrams
                    }
                    .foregroundStyle(theme.accent)
                }

                // Makros
                Section("Nährwerte für Portion") {
                    nutriRow("Eiweiß",        value: portion.protein)
                    nutriRow("Kohlenhydrate", value: portion.carbs)
                    nutriRow("Fett",          value: portion.fat)
                }

                // Zutaten
                Section("Zutaten (Rezept: \(Int(recipe.totalCookedWeightGrams)) g)") {
                    ForEach(recipe.ingredients) { ing in
                        HStack {
                            Text(ing.food?.name ?? "?")
                            Spacer()
                            Text("\(Int(ing.grams)) g")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Ins Tagebuch
                Section("Ins Tagebuch eintragen") {
                    DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                    Picker("Mahlzeit", selection: $selectedMeal) {
                        ForEach(MealType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Button { logRecipe() } label: {
                        Label("Hinzufügen", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func nutriRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.1f g", value)).foregroundStyle(.secondary)
        }
    }

    private func logRecipe() {
        // Snapshot-Food pro Log-Vorgang (Kalorien passen exakt zur Portion)
        let n100 = recipe.nutrition(for: 100)
        let nutrition = Nutrition(
            kcal:    n100.kcal,
            protein: n100.protein,
            carbs:   n100.carbs,
            fat:     n100.fat
        )
        let food = Food(name: recipe.name, source: .recipe, nutritionPer100g: nutrition)
        modelContext.insert(food)

        let entry = DiaryEntry(date: selectedDate, meal: selectedMeal, food: food, grams: grams)
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
