import SwiftUI
import SwiftData

// MARK: - CustomFoodSheet
// Erstellen (food == nil) oder Bearbeiten (food != nil) eines eigenen Lebensmittels.

struct CustomFoodSheet: View {
    var food: Food? = nil                      // nil = neu anlegen
    var onCreated: ((Food) -> Void)? = nil     // nur beim Erstellen genutzt

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var name:  String = ""
    @State private var brand: String = ""

    @State private var kcal:    Double = 0
    @State private var protein: Double = 0
    @State private var carbs:   Double = 0
    @State private var fat:     Double = 0

    @State private var showOptional   = false
    @State private var fiber:         Double = 0
    @State private var sugar:         Double = 0
    @State private var saturatedFat:  Double = 0
    @State private var salt:          Double = 0

    @State private var hasServing:   Bool   = false
    @State private var servingGrams: Double = 100
    @State private var unit:         FoodUnit        = .grams
    @State private var portions:     [FoodPortion]   = []

    private var isEditing: Bool { food != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kcal > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezeichnung") {
                    TextField("Name (Pflichtfeld)", text: $name)
                    TextField("Marke (optional)", text: $brand)
                    Picker("Einheit", selection: $unit) {
                        ForEach(FoodUnit.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }

                Section {
                    nutriField("Kalorien",      value: $kcal,    unit: "kcal", required: true)
                    nutriField("Eiweiß",        value: $protein, unit: "g")
                    nutriField("Kohlenhydrate", value: $carbs,   unit: "g")
                    nutriField("Fett",          value: $fat,     unit: "g")
                } header: {
                    Text("Nährwerte pro 100 g")
                } footer: {
                    Text("Alle Angaben beziehen sich auf 100 g.")
                }

                Section {
                    Toggle("Erweiterte Nährwerte", isOn: $showOptional.animation())
                    if showOptional {
                        nutriField("Ballaststoffe",   value: $fiber,        unit: "g")
                        nutriField("davon Zucker",    value: $sugar,        unit: "g")
                        nutriField("ges. Fettsäuren", value: $saturatedFat, unit: "g")
                        nutriField("Salz",            value: $salt,         unit: "g")
                    }
                }

                Section {
                    Toggle("Standardportion", isOn: $hasServing.animation())
                    if hasServing {
                        NumericStepperView(value: $servingGrams, range: 1...2000, step: 5, unit: unit.rawValue)
                    }
                } footer: {
                    if hasServing {
                        Text("Wird beim Eintragen vorausgewählt.")
                    }
                }

                Section {
                    ForEach($portions) { $portion in
                        HStack {
                            TextField("Name (z. B. 1 Scheibe)", text: $portion.name)
                            Divider()
                            TextField("0", value: $portion.grams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { portions.remove(atOffsets: $0) }

                    Button {
                        portions.append(FoodPortion(name: "", grams: 0))
                    } label: {
                        Label("Portion hinzufügen", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Portionsgrößen")
                } footer: {
                    Text("Benannte Portionen (z. B. \"1 Scheibe ≈ 15 g\") für schnelle Auswahl.")
                }
            }
            .navigationTitle(isEditing ? "Lebensmittel bearbeiten" : "Eigenes Lebensmittel")
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
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Hilfsmethoden

    private func nutriField(
        _ label: String,
        value: Binding<Double>,
        unit: String,
        required: Bool = false
    ) -> some View {
        HStack {
            Text(label)
            if required { Text("*").foregroundStyle(.red).font(.caption) }
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
        }
    }

    private func loadExisting() {
        guard let f = food else { return }
        name  = f.name
        brand = f.brand ?? ""

        if let n = f.nutritionPer100g {
            kcal    = n.kcal
            protein = n.protein
            carbs   = n.carbs
            fat     = n.fat
            if let v = n.fiber        { fiber        = v; showOptional = true }
            if let v = n.sugar        { sugar        = v; showOptional = true }
            if let v = n.saturatedFat { saturatedFat = v; showOptional = true }
            if let v = n.salt         { salt         = v; showOptional = true }
        }
        if let s = f.defaultServingGrams { servingGrams = s; hasServing = true }
        unit     = f.unit
        portions = f.portions
    }

    private func save() {
        let cleanPortions = portions.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.grams > 0 }
        if let existing = food {
            // Bearbeiten
            existing.name  = name.trimmingCharacters(in: .whitespaces)
            existing.brand = brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
            existing.defaultServingGrams = hasServing ? servingGrams : nil
            existing.unit     = unit
            existing.portions = cleanPortions
            if let n = existing.nutritionPer100g {
                n.kcal    = kcal;  n.protein = protein
                n.carbs   = carbs; n.fat     = fat
                n.fiber        = showOptional && fiber        > 0 ? fiber        : nil
                n.sugar        = showOptional && sugar        > 0 ? sugar        : nil
                n.saturatedFat = showOptional && saturatedFat > 0 ? saturatedFat : nil
                n.salt         = showOptional && salt         > 0 ? salt         : nil
            }
        } else {
            // Neu anlegen
            let n = Nutrition(
                kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                fiber:        showOptional && fiber        > 0 ? fiber        : nil,
                sugar:        showOptional && sugar        > 0 ? sugar        : nil,
                salt:         showOptional && salt         > 0 ? salt         : nil,
                saturatedFat: showOptional && saturatedFat > 0 ? saturatedFat : nil
            )
            let f = Food(
                name:  name.trimmingCharacters(in: .whitespaces),
                brand: brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
                source: .custom, nutritionPer100g: n,
                defaultServingGrams: hasServing ? servingGrams : nil
            )
            f.unit     = unit
            f.portions = cleanPortions
            modelContext.insert(f)
            try? modelContext.save()
            onCreated?(f)
            dismiss()
            return
        }
        try? modelContext.save()
        dismiss()
    }
}
