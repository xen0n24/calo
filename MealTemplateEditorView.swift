import SwiftUI
import SwiftData

// MARK: - MealTemplateEditorView

struct MealTemplateEditorView: View {
    var existingTemplate: MealTemplate? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var name:          String = ""
    @State private var mealType:      MealType = .breakfast
    @State private var drafts:        [TemplateDraft] = []
    @State private var showFoodPicker = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !drafts.isEmpty
    }

    private var totalKcal: Double {
        drafts.reduce(0) { $0 + $1.food.nutrition(for: $1.grams).kcal }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorlagenname") {
                    TextField("z.B. Mein Standard-Frühstück", text: $name)
                }

                Section("Standard-Mahlzeit") {
                    Picker("Mahlzeit", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        showFoodPicker = true
                    } label: {
                        Label("Lebensmittel hinzufügen", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Lebensmittel")
                } footer: {
                    if !drafts.isEmpty {
                        Text("Gesamt: \(Int(totalKcal)) kcal · \(drafts.count) Einträge")
                    }
                }
            }
            .navigationTitle(existingTemplate == nil ? "Neue Vorlage" : "Vorlage bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadExisting() }
            .sheet(isPresented: $showFoodPicker) {
                TemplateFoodPickerSheet { food, grams in
                    drafts.append(TemplateDraft(food: food, grams: grams))
                }
            }
        }
    }

    // MARK: - Laden / Speichern

    private func loadExisting() {
        guard let t = existingTemplate else { return }
        name     = t.name
        mealType = t.mealType
        drafts   = t.entries.compactMap { entry in
            guard let food = entry.food else { return nil }
            return TemplateDraft(food: food, grams: entry.grams)
        }
    }

    private func save() {
        let template: MealTemplate
        if let existing = existingTemplate {
            template = existing
        } else {
            template = MealTemplate(name: name.trimmingCharacters(in: .whitespaces), mealType: mealType)
            modelContext.insert(template)
        }

        template.name     = name.trimmingCharacters(in: .whitespaces)
        template.mealType = mealType

        // Alte Einträge löschen, neue anlegen
        for entry in template.entries { modelContext.delete(entry) }
        template.entries = drafts.map { draft in
            let e = TemplateEntry(food: draft.food, grams: draft.grams)
            modelContext.insert(e)
            e.template = template
            return e
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - TemplateFoodPickerSheet

struct TemplateFoodPickerSheet: View {
    let onSelect:      (Food, Double) -> Void
    let initialSearch: String

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var allFoods: [Food]

    @State private var searchText: String
    @State private var pickedFood: Food? = nil
    @State private var grams: Double = 100

    init(initialSearch: String = "", onSelect: @escaping (Food, Double) -> Void) {
        self.initialSearch = initialSearch
        self.onSelect      = onSelect
        _searchText        = State(initialValue: initialSearch)
    }

    private var results: [Food] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return Array(allFoods.filter { $0.source != .recipe }.prefix(30))
        }
        return allFoods
            .filter { $0.source != .recipe && $0.name.localizedCaseInsensitiveContains(q) }
            .prefix(20).map { $0 }
    }

    var body: some View {
        NavigationStack {
            if let food = pickedFood {
                // Mengenauswahl
                Form {
                    Section {
                        LabeledContent("Lebensmittel", value: food.name)
                        LabeledContent("Kalorien", value: "\(Int(food.nutrition(for: grams).kcal)) kcal")
                            .foregroundStyle(.green)
                    }
                    Section("Menge") {
                        NumericStepperView(value: $grams, range: 1...5_000, step: 5, unit: "g")
                    }
                }
                .navigationTitle("Menge")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Zurück") { pickedFood = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hinzufügen") {
                            onSelect(food, grams)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            } else {
                // Lebensmittelliste
                List {
                    ForEach(results) { food in
                        Button {
                            grams = food.defaultServingGrams ?? 100
                            pickedFood = food
                        } label: {
                            FoodResultRow(
                                name:   food.name,
                                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                                badge:  food.brand
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .searchable(text: $searchText, prompt: "Lebensmittel suchen…")
                .navigationTitle("Lebensmittel wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
            }
        }
    }
}
