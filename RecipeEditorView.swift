import SwiftUI
import SwiftData

// MARK: - IngredientDraft (Identifiable → sicheres ForEach)

private struct IngredientDraft: Identifiable {
    let id   = UUID()
    let food: Food
    var grams: Double
}

// MARK: - RecipeEditorView

struct RecipeEditorView: View {
    var recipe: Recipe? = nil

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @State private var name:         String = ""
    @State private var totalGrams:   Double = 500
    @State private var instructions: String = ""
    @State private var drafts:       [IngredientDraft] = []
    @State private var showPicker    = false

    private var totalKcal: Double {
        drafts.reduce(0) { $0 + $1.food.nutrition(for: $1.grams).kcal }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rezeptname") {
                    TextField("z.B. Bolognese", text: $name)
                }

                Section {
                    NumericStepperView(value: $totalGrams, range: 50...10_000, step: 50, unit: "g")
                } header: {
                    Text("Gesamtgewicht nach dem Kochen")
                } footer: {
                    Text("Grundlage für die gramm-basierte Skalierung.")
                }

                Section {
                    ForEach(drafts) { draft in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.food.name).font(.subheadline)
                                Text("\(Int(draft.grams)) g")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(draft.food.nutrition(for: draft.grams).kcal)) kcal")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in drafts.remove(atOffsets: offsets) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Zutat hinzufügen", systemImage: "plus.circle")
                            .foregroundStyle(theme.accent)
                    }
                } header: {
                    Text("Zutaten")
                } footer: {
                    if !drafts.isEmpty {
                        Text("Gesamt: \(Int(totalKcal)) kcal · \(drafts.count) Zutaten")
                    }
                }

                Section("Zubereitung (optional)") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(recipe == nil ? "Neues Rezept" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPicker) {
                IngredientPickerSheet { food, grams in
                    drafts.append(IngredientDraft(food: food, grams: grams))
                }
            }
        }
        .onAppear { loadDraft() }
    }

    // MARK: - Laden

    private func loadDraft() {
        guard let r = recipe else { return }
        name         = r.name
        totalGrams   = r.totalCookedWeightGrams
        instructions = r.instructions ?? ""
        drafts = r.ingredients.compactMap { ing in
            guard let food = ing.food else { return nil }
            return IngredientDraft(food: food, grams: ing.grams)
        }
    }

    // MARK: - Speichern

    private func save() {
        let target: Recipe
        if let existing = recipe {
            target = existing
        } else {
            target = Recipe(name: name, totalCookedWeightGrams: totalGrams)
            modelContext.insert(target)
        }

        target.name                   = name.trimmingCharacters(in: .whitespaces)
        target.totalCookedWeightGrams = totalGrams
        target.instructions           = instructions.isEmpty ? nil : instructions

        // Alte Zutaten löschen
        for ing in target.ingredients { modelContext.delete(ing) }
        target.ingredients = []

        // Neue Zutaten aus Drafts
        for draft in drafts {
            let ing = RecipeIngredient(food: draft.food, grams: draft.grams)
            ing.recipe = target
            modelContext.insert(ing)
            target.ingredients.append(ing)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - IngredientPickerSheet

struct IngredientPickerSheet: View {
    let onSelect: (Food, Double) -> Void

    @Environment(AppTheme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query private var allFoods: [Food]

    @State private var searchText      = ""
    @State private var selectedFood: Food? = nil
    @State private var grams: Double   = 100

    private var results: [Food] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allFoods
            .filter { $0.source != .recipe && $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name < $1.name }
            .prefix(25).map { $0 }
    }

    var body: some View {
        NavigationStack {
            if let food = selectedFood {
                amountView(food: food)
                    .navigationTitle("Menge")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zurück") { selectedFood = nil }
                        }
                    }
            } else {
                List {
                    if !searchText.isEmpty && results.isEmpty {
                        Text("Kein Lebensmittel gefunden.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { food in
                        Button {
                            grams = food.defaultServingGrams ?? 100
                            selectedFood = food
                        } label: {
                            FoodResultRow(
                                name:   food.name,
                                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                                badge:  nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .searchable(text: $searchText, prompt: "Zutat suchen…")
                .navigationTitle("Zutat wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
            }
        }
    }

    private func amountView(food: Food) -> some View {
        VStack(spacing: 32) {
            VStack(spacing: 6) {
                Text(food.name).font(.title2.bold())
                Text("\(Int((food.nutritionPer100g?.kcal ?? 0) * grams / 100)) kcal für \(Int(grams)) g")
                    .foregroundStyle(.secondary)
            }
            NumericStepperView(value: $grams, range: 1...5_000, step: 5, unit: "g")
            Button {
                onSelect(food, grams)
                dismiss()
            } label: {
                Label("Zur Zutatenliste", systemImage: "plus")
                    .frame(maxWidth: .infinity).padding().font(.headline)
            }
            .buttonStyle(.borderedProminent).tint(theme.accent).padding(.horizontal)
            Spacer()
        }
        .padding(.top, 24)
    }
}
