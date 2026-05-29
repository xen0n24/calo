# Favoriten, Meal Templates, Körpermaße – Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Favoriten für Lebensmittel/Rezepte, Mahlzeit-Vorlagen (aus Tagebuch speichern oder manuell erstellen, per Button einfügen) und optionale Körpermaße (frei konfigurierbar, Verlauf in Statistik) implementieren.

**Architecture:** Alle neuen Daten in SwiftData (keine AppStorage für Content). Body-Measurements-Feature per `@AppStorage("feature.bodyMeasurements.enabled")` ein-/ausschaltbar. Muster aus RecipeEditorView / DiaryDateContent übernehmen.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 26. Kein git, kein Testsystem — Verifizierung durch Transfer auf iPad und Build in Swift Playgrounds.

> **Swift Playgrounds Limits:** Kein verschachteltes `List` in `List` (immer `ForEach`). `ForEach` mit .onDelete nur mit `Identifiable`-Struct. Kein `@retroactive` auf eigene `@Model`-Typen.

---

## Dateien

| Datei | Aktion |
|---|---|
| `Models.swift` | Ändern: `isFavorite` auf Food + Recipe; neue Models MealTemplate, TemplateEntry, BodyMeasurementType, BodyMeasurement |
| `CaloApp.swift` | Ändern: 4 neue Modelle in ModelContainer |
| `FoodSearchSheet.swift` | Ändern: Favoriten-Tab + Favorit-Swipe-Action |
| `SearchView.swift` | Ändern: Favorit-Swipe-Action auf Lebensmittel |
| `RecipesView.swift` | Ändern: Favorit-Swipe-Action auf Rezepte |
| `MealTemplateEditorView.swift` | Neu: manueller Template-Editor |
| `DiaryView.swift` | Ändern: MealSectionCard bekommt 2 neue Callbacks + SaveTemplate/InsertTemplate Sheets |
| `ProfileView.swift` | Ändern: Sektion "Vorlagen", "Körpermaße", "Optionale Features" |
| `StatsView.swift` | Ändern: Körpermaße-Sektion mit Chart + Logger-Sheet |

---

## Task 1: Datenmodell erweitern

**Files:**
- Modify: `Models.swift`
- Modify: `CaloApp.swift`

- [ ] **Schritt 1: `isFavorite` zu Food und Recipe hinzufügen**

In `Models.swift`, in der `Food`-Klasse nach `var createdAt: Date` einfügen:
```swift
var isFavorite: Bool = false
```

In `Models.swift`, in der `Recipe`-Klasse nach `var instructions: String?` einfügen:
```swift
var isFavorite: Bool = false
```

- [ ] **Schritt 2: MealTemplate und TemplateEntry hinzufügen**

Am Ende von `Models.swift` vor dem letzten `// MARK: - Recipe-Berechnungen` Block einfügen:

```swift
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
        self.id       = id
        self.name     = name
        self.mealType = mealType
        self.entries  = []
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
    @Relationship(deleteRule: .cascade, inverse: \BodyMeasurement.type)
    var measurements: [BodyMeasurement] = []

    init(id: UUID = UUID(), name: String, unit: String, sortOrder: Int = 0) {
        self.id        = id
        self.name      = name
        self.unit      = unit
        self.sortOrder = sortOrder
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
```

- [ ] **Schritt 3: Neue Modelle in CaloApp.swift registrieren**

In `CaloApp.swift` den ModelContainer-Aufruf ersetzen:

```swift
container = try ModelContainer(for:
    Food.self,
    Nutrition.self,
    DiaryEntry.self,
    WeightEntry.self,
    UserProfile.self,
    Recipe.self,
    RecipeIngredient.self,
    WaterLog.self,
    MealTemplate.self,
    TemplateEntry.self,
    BodyMeasurementType.self,
    BodyMeasurement.self
)
```

- [ ] **Schritt 4: iPad-Transfer-Checkpoint**

Dateien übertragen: `Models.swift`, `CaloApp.swift`. In Swift Playgrounds öffnen und sicherstellen dass es kompiliert (Run). Kein neues UI erwartet — nur Schemaerweiterung.

---

## Task 2: Favoriten-Tab im FoodSearchSheet

**Files:**
- Modify: `FoodSearchSheet.swift`

- [ ] **Schritt 1: State und Queries für Favoriten hinzufügen**

In `FoodSearchSheet` (nach den bestehenden `@Query`-Properties) einfügen:

```swift
@Query(filter: #Predicate<Food>   { $0.isFavorite == true }, sort: \Food.name)
    private var favoriteFoods: [Food]
@Query(filter: #Predicate<Recipe> { $0.isFavorite == true }, sort: \Recipe.name)
    private var favoriteRecipes: [Recipe]

@State private var showFavorites = false
```

- [ ] **Schritt 2: `searchListView` um Favoriten-Tab erweitern**

Im `searchListView` computed property, die erste `if searchText.isEmpty {` Sektion ersetzen. Derzeit beginnt der Block mit `// Vorschläge: zuletzt & häufig genutzte Foods`. Den gesamten `if searchText.isEmpty { ... }` Block ersetzen durch:

```swift
if searchText.isEmpty {
    // Tab-Picker
    Section {
        Picker("", selection: $showFavorites) {
            Text("Vorschläge").tag(false)
            Text("Favoriten").tag(true)
        }
        .pickerStyle(.segmented)
    }
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

    if showFavorites {
        // ── Favoriten-Tab ──
        if favoriteFoods.isEmpty && favoriteRecipes.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Keine Favoriten", systemImage: "heart")
                } description: {
                    Text("Wische nach rechts auf ein Lebensmittel oder Rezept, um es zu favorisieren.")
                }
            }
            .listRowBackground(Color.clear)
        } else {
            if !favoriteFoods.isEmpty {
                Section("Lebensmittel") {
                    ForEach(favoriteFoods) { food in
                        Button { pick(.local(food)) } label: {
                            FoodResultRow(
                                name:   food.name,
                                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                                badge:  food.brand
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            favoriteSwipeButton(isFavorite: true) {
                                food.isFavorite = false
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
            if !favoriteRecipes.isEmpty {
                Section("Rezepte") {
                    ForEach(favoriteRecipes) { recipe in
                        Button { pick(.recipe(recipe)) } label: {
                            FoodResultRow(
                                name:   recipe.name,
                                detail: "\(Int(recipe.kcalPer100g)) kcal / 100 g",
                                badge:  nil
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            favoriteSwipeButton(isFavorite: true) {
                                recipe.isFavorite = false
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
        }
    } else {
        // ── Vorschläge-Tab (bisheriger Code) ──
        if !recentFoods.isEmpty {
            Section("Zuletzt verwendet") {
                ForEach(recentFoods) { food in
                    suggestedFoodRow(food)
                        .swipeActions(edge: .leading) {
                            favoriteSwipeButton(isFavorite: food.isFavorite) {
                                food.isFavorite.toggle()
                                try? modelContext.save()
                            }
                        }
                }
            }
        }
        if !frequentFoods.isEmpty {
            Section("Häufig verwendet") {
                ForEach(frequentFoods) { food in
                    suggestedFoodRow(food)
                        .swipeActions(edge: .leading) {
                            favoriteSwipeButton(isFavorite: food.isFavorite) {
                                food.isFavorite.toggle()
                                try? modelContext.save()
                            }
                        }
                }
            }
        }
        if recentFoods.isEmpty && frequentFoods.isEmpty {
            searchHint
        }
    }
```

Außerdem in den Suchergebnissen (im `else`-Zweig, Sektion "Meine Lebensmittel") Swipe-Action ergänzen:

```swift
Section("Meine Lebensmittel") {
    ForEach(localResults) { food in
        Button { pick(.local(food)) } label: {
            FoodResultRow(
                name:   food.name,
                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                badge:  nil
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            favoriteSwipeButton(isFavorite: food.isFavorite) {
                food.isFavorite.toggle()
                try? modelContext.save()
            }
        }
    }
}
```

- [ ] **Schritt 3: Hilfsfunktion `favoriteSwipeButton` hinzufügen**

In `FoodSearchSheet`, nach `private var emptyState` einfügen:

```swift
private func favoriteSwipeButton(isFavorite: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(
            isFavorite ? "Entfernen" : "Favorit",
            systemImage: isFavorite ? "heart.slash.fill" : "heart.fill"
        )
    }
    .tint(isFavorite ? .gray : .pink)
}
```

- [ ] **Schritt 4: iPad-Transfer-Checkpoint**

Datei übertragen: `FoodSearchSheet.swift`. Testen: Tagebuch → „+" → Favoriten-Tab erscheint → Vorschläge-Tab funktioniert wie vorher → Swipe nach rechts auf Lebensmittel zeigt Herz-Button.

---

## Task 3: Favoriten-Swipe in SearchView und RecipesView

**Files:**
- Modify: `SearchView.swift`
- Modify: `RecipesView.swift`

- [ ] **Schritt 1: Favorit-Swipe in SearchView (Lebensmittel-Liste)**

In `SearchView` die Vorschläge-Rows und lokale Suchergebnisse mit Swipe-Action ergänzen. Die Hilfsfunktion direkt in SearchView definieren (analog zu FoodSearchSheet):

```swift
// Am Ende von SearchView als private func einfügen:
private func favoriteSwipeButton(isFavorite: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(
            isFavorite ? "Entfernen" : "Favorit",
            systemImage: isFavorite ? "heart.slash.fill" : "heart.fill"
        )
    }
    .tint(isFavorite ? .gray : .pink)
}
```

Dann in der Lebensmittel-Liste (SearchView) überall wo `FoodDetailRow` oder Food-Rows gerendert werden, `.swipeActions(edge: .leading)` ergänzen:

Für recentFoods/frequentFoods Rows:
```swift
.swipeActions(edge: .leading) {
    favoriteSwipeButton(isFavorite: food.isFavorite) {
        food.isFavorite.toggle()
        try? modelContext.save()
    }
}
```

Für localFoods Rows (Suchergebnisse):
```swift
.swipeActions(edge: .leading) {
    favoriteSwipeButton(isFavorite: food.isFavorite) {
        food.isFavorite.toggle()
        try? modelContext.save()
    }
}
```

- [ ] **Schritt 2: Favorit-Swipe in RecipesView**

In `RecipesView`, in `recipeList`, im `ForEach` block nach der bestehenden `.swipeActions(edge: .trailing)` eine zweite Swipe-Action hinzufügen:

```swift
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
```

- [ ] **Schritt 3: iPad-Transfer-Checkpoint**

Dateien übertragen: `SearchView.swift`, `RecipesView.swift`. Testen: Suche-Tab → Lebensmittel → Swipe nach rechts = Favorit-Button. Rezepte-Tab → Swipe nach links = Löschen/Bearbeiten, Swipe nach rechts = Favorit.

---

## Task 4: MealTemplateEditorView (neue Datei)

**Files:**
- Create: `MealTemplateEditorView.swift`

- [ ] **Schritt 1: Datei anlegen**

Neue Datei `MealTemplateEditorView.swift` im Root erstellen:

```swift
import SwiftUI
import SwiftData

// MARK: - MealTemplateEditorView

struct MealTemplateEditorView: View {
    var existingTemplate: MealTemplate? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var name:     String = ""
    @State private var mealType: MealType = .breakfast
    @State private var drafts:   [TemplateDraft] = []
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
        let template = existingTemplate ?? {
            let t = MealTemplate(name: name.trimmingCharacters(in: .whitespaces), mealType: mealType)
            modelContext.insert(t)
            return t
        }()

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
    let onSelect: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var allFoods: [Food]

    @State private var searchText = ""
    @State private var pickedFood: Food? = nil
    @State private var grams: Double = 100

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
```

- [ ] **Schritt 2: iPad-Transfer-Checkpoint**

Datei übertragen: `MealTemplateEditorView.swift`. In Swift Playgrounds prüfen ob es kompiliert. Noch keine Verbindung zum UI — nächste Tasks bauen das an.

---

## Task 5: Vorlagen im Tagebuch (DiaryView)

**Files:**
- Modify: `DiaryView.swift`

- [ ] **Schritt 1: MealSectionCard-Interface erweitern**

`MealSectionCard` bekommt zwei neue Parameter. Die Struct-Definition ändern:

```swift
struct MealSectionCard: View {
    let meal:             MealType
    let entries:          [DiaryEntry]
    let onAdd:            () -> Void
    let onDelete:         (DiaryEntry) -> Void
    let onEdit:           (DiaryEntry) -> Void
    let onSaveAsTemplate: () -> Void    // NEU
    let onInsertTemplate: () -> Void    // NEU
    ...
```

Den `+`-Button in `MealSectionCard` ersetzen (aktuell `Button(action: onAdd) { Image(systemName: "plus.circle.fill") ... }`):

```swift
Menu {
    Button { onAdd() } label: {
        Label("Lebensmittel hinzufügen", systemImage: "fork.knife")
    }
    Button { onInsertTemplate() } label: {
        Label("Vorlage einfügen", systemImage: "doc.on.clipboard")
    }
    if !entries.isEmpty {
        Divider()
        Button { onSaveAsTemplate() } label: {
            Label("Als Vorlage speichern", systemImage: "square.and.arrow.down")
        }
    }
} label: {
    Image(systemName: "plus.circle.fill")
        .font(.title3)
        .foregroundStyle(.green)
}
```

- [ ] **Schritt 2: DiaryDateContent — State und Sheets hinzufügen**

In `DiaryDateContent` neue State-Properties nach `@State private var editingEntry` einfügen:

```swift
@State private var showSaveTemplate       = false
@State private var showInsertTemplate     = false
@State private var activeTemplateMeal:  MealType = .breakfast
@State private var templateName           = ""
```

Query für Templates hinzufügen (nach den bestehenden `@Query`-Properties):

```swift
@Query(sort: \MealTemplate.name) private var allTemplates: [MealTemplate]
```

- [ ] **Schritt 3: DiaryDateContent — MealSectionCard-Aufrufe aktualisieren**

Den bestehenden `MealSectionCard(...)` Aufruf im `body` erweitern:

```swift
MealSectionCard(
    meal:    meal,
    entries: entries.filter { $0.meal == meal },
    onAdd:   { onAddEntry(meal) },
    onDelete: deleteEntry,
    onEdit:  { editingEntry = $0 },
    onSaveAsTemplate: {
        activeTemplateMeal = meal
        templateName       = ""
        showSaveTemplate   = true
    },
    onInsertTemplate: {
        activeTemplateMeal  = meal
        showInsertTemplate  = true
    }
)
```

- [ ] **Schritt 4: DiaryDateContent — Sheets registrieren**

Nach dem bestehenden `.sheet(item: $editingEntry)` Modifier weitere Sheets anhängen:

```swift
// Vorlage speichern
.sheet(isPresented: $showSaveTemplate) {
    SaveTemplateSheet(
        meal:         activeTemplateMeal,
        entries:      entries.filter { $0.meal == activeTemplateMeal },
        initialName:  templateName
    )
}
// Vorlage einfügen
.sheet(isPresented: $showInsertTemplate) {
    InsertTemplateSheet(
        templates: allTemplates,
        date:      date,
        meal:      activeTemplateMeal
    )
}
```

- [ ] **Schritt 5: SaveTemplateSheet und InsertTemplateSheet hinzufügen**

Am Ende von `DiaryView.swift` (nach `DiaryEntryEditSheet`) einfügen:

```swift
// MARK: - SaveTemplateSheet

struct SaveTemplateSheet: View {
    let meal:        MealType
    let entries:     [DiaryEntry]
    let initialName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !entries.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorlagenname") {
                    TextField("z.B. Mein Standard-Frühstück", text: $name)
                }
                Section("Enthält \(entries.count) Einträge aus \(meal.rawValue)") {
                    ForEach(entries) { entry in
                        LabeledContent(
                            entry.food?.name ?? "?",
                            value: "\(Int(entry.grams)) g"
                        )
                    }
                }
            }
            .navigationTitle("Als Vorlage speichern")
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
            .onAppear { name = initialName }
        }
    }

    private func save() {
        let t = MealTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            mealType: meal
        )
        modelContext.insert(t)
        for entry in entries {
            guard let food = entry.food else { continue }
            let te = TemplateEntry(food: food, grams: entry.grams)
            modelContext.insert(te)
            te.template = t
            t.entries.append(te)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - InsertTemplateSheet

struct InsertTemplateSheet: View {
    let templates: [MealTemplate]
    let date:      Date
    let meal:      MealType

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Vorlagen", systemImage: "doc.on.clipboard")
                    } description: {
                        Text("Erstelle Vorlagen über das Menü bei einer Mahlzeit oder unter Profil → Vorlagen.")
                    }
                } else {
                    List {
                        ForEach(templates) { template in
                            Button { insert(template) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(template.entries.count) Einträge · \(template.mealType.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Vorlage einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func insert(_ template: MealTemplate) {
        let day = Calendar.current.startOfDay(for: date)
        for entry in template.entries {
            guard let food = entry.food else { continue }
            let diaryEntry = DiaryEntry(date: day, meal: meal, food: food, grams: entry.grams)
            modelContext.insert(diaryEntry)
        }
        try? modelContext.save()
        dismiss()
    }
}
```

- [ ] **Schritt 6: iPad-Transfer-Checkpoint**

Datei übertragen: `DiaryView.swift`. Testen:
- Tagebuch → „+" Menü bei einer Mahlzeit → „Vorlage einfügen" und „Lebensmittel hinzufügen" sichtbar
- „Als Vorlage speichern" nur sichtbar wenn Einträge vorhanden
- Vorlage speichern → Name eingeben → Speichern
- Vorlage einfügen → gespeicherte Vorlage auswählen → Einträge erscheinen

---

## Task 6: ProfileView — Vorlagen-Verwaltung + Body-Measurements-Toggle

**Files:**
- Modify: `ProfileView.swift`

- [ ] **Schritt 1: Neue AppStorage-Properties und Queries hinzufügen**

In `ProfileView` nach den bestehenden `@AppStorage`-Properties einfügen:

```swift
@AppStorage("feature.bodyMeasurements.enabled") private var bodyMeasurementsEnabled = false
```

Neue `@Query`-Properties hinzufügen:

```swift
@Query(sort: \MealTemplate.createdAt, order: .reverse) private var templates: [MealTemplate]
@Query(sort: \BodyMeasurementType.sortOrder) private var measurementTypes: [BodyMeasurementType]
```

Neue `@State`-Properties:

```swift
@State private var showTemplateEditor        = false
@State private var editingTemplate: MealTemplate? = nil
@State private var showAddMeasurementType    = false
@State private var newMeasurementName        = ""
@State private var newMeasurementUnit        = ""
```

- [ ] **Schritt 2: Sektion „Vorlagen" in der List hinzufügen**

Im `body` der `ProfileView`, nach der „Erinnerungen"-Sektion und vor der „Profil zurücksetzen"-Sektion einfügen:

```swift
// MARK: Vorlagen
Section {
    ForEach(templates) { template in
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.subheadline.weight(.medium))
                Text("\(template.entries.count) Einträge · \(template.mealType.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { editingTemplate = template } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
    .onDelete { offsets in deleteTemplates(at: offsets) }

    Button {
        showTemplateEditor = true
    } label: {
        Label("Neue Vorlage", systemImage: "plus.circle")
            .foregroundStyle(.green)
    }
} header: {
    Text("Vorlagen")
} footer: {
    Text("Vorlagen können im Tagebuch per Menü bei einer Mahlzeit eingefügt werden.")
}
```

- [ ] **Schritt 3: Sektion „Optionale Features" und „Körpermaße" hinzufügen**

Nach der „Vorlagen"-Sektion einfügen:

```swift
// MARK: Optionale Features
Section("Optionale Features") {
    Toggle("Körpermaße aktivieren", isOn: $bodyMeasurementsEnabled)
}

// MARK: Körpermaße (nur wenn aktiviert)
if bodyMeasurementsEnabled {
    Section {
        ForEach(measurementTypes) { type in
            LabeledContent(type.name, value: "in \(type.unit)")
        }
        .onDelete { offsets in deleteMeasurementTypes(at: offsets) }

        Button {
            newMeasurementName = ""
            newMeasurementUnit = ""
            showAddMeasurementType = true
        } label: {
            Label("Neues Maß hinzufügen", systemImage: "plus.circle")
                .foregroundStyle(.green)
        }
    } header: {
        Text("Körpermaße")
    } footer: {
        Text("Messungen werden unter Statistik erfasst und als Verlauf angezeigt. Löschen entfernt alle Einträge für dieses Maß.")
    }
}
```

- [ ] **Schritt 4: Sheet-Modifier und Hilfsfunktionen hinzufügen**

Bestehende `.sheet`-Modifier erweitern (nach `.sheet(isPresented: $showEdit)`):

```swift
.sheet(isPresented: $showTemplateEditor) {
    MealTemplateEditorView()
}
.sheet(item: $editingTemplate) { t in
    MealTemplateEditorView(existingTemplate: t)
}
.sheet(isPresented: $showAddMeasurementType) {
    AddMeasurementTypeSheet(name: $newMeasurementName, unit: $newMeasurementUnit) {
        let count = measurementTypes.count
        let t = BodyMeasurementType(
            name: newMeasurementName.trimmingCharacters(in: .whitespaces),
            unit: newMeasurementUnit.trimmingCharacters(in: .whitespaces),
            sortOrder: count
        )
        modelContext.insert(t)
        try? modelContext.save()
    }
}
```

Hilfsfunktionen am Ende von ProfileView einfügen:

```swift
private func deleteTemplates(at offsets: IndexSet) {
    for i in offsets { modelContext.delete(templates[i]) }
    try? modelContext.save()
}

private func deleteMeasurementTypes(at offsets: IndexSet) {
    for i in offsets { modelContext.delete(measurementTypes[i]) }
    try? modelContext.save()
}
```

- [ ] **Schritt 5: AddMeasurementTypeSheet hinzufügen**

Am Ende von `ProfileView.swift` (nach der Struct) einfügen:

```swift
// MARK: - AddMeasurementTypeSheet

struct AddMeasurementTypeSheet: View {
    @Binding var name: String
    @Binding var unit: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !unit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z.B. Taille", text: $name)
                }
                Section("Einheit") {
                    TextField("z.B. cm", text: $unit)
                }
            }
            .navigationTitle("Neues Maß")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
```

- [ ] **Schritt 6: iPad-Transfer-Checkpoint**

Datei übertragen: `ProfileView.swift`. Testen:
- Profil → Sektion „Vorlagen" sichtbar
- „Neue Vorlage" öffnet Editor → Vorlage anlegen → erscheint in Liste
- Swipe-to-Delete auf Vorlage funktioniert
- Toggle „Körpermaße aktivieren" → Sektion „Körpermaße" erscheint/verschwindet
- „Neues Maß hinzufügen" → Name + Einheit eingeben → erscheint in Liste
- Swipe-to-Delete auf Maß funktioniert

---

## Task 7: Körpermaße in StatsView

**Files:**
- Modify: `StatsView.swift`

- [ ] **Schritt 1: AppStorage + Queries hinzufügen**

In `StatsView` nach den bestehenden Properties einfügen:

```swift
@AppStorage("feature.bodyMeasurements.enabled") private var bodyMeasurementsEnabled = false
@Query(sort: \BodyMeasurementType.sortOrder) private var measurementTypes: [BodyMeasurementType]
@Query(sort: \BodyMeasurement.date) private var allBodyMeasurements: [BodyMeasurement]

@State private var showBodyMeasurementLogger = false
@State private var selectedMeasurementType: BodyMeasurementType? = nil
```

- [ ] **Schritt 2: Körpermaße-Sektion in body einbinden**

In `StatsView.body`, in der `List`, nach `adaptiveSection` einfügen:

```swift
if bodyMeasurementsEnabled && !measurementTypes.isEmpty {
    bodyMeasurementsSection
}
```

Und den `showWeightLogger`-Sheet um den Körpermaße-Logger erweitern:

```swift
.sheet(isPresented: $showBodyMeasurementLogger) {
    BodyMeasurementLoggerSheet(types: measurementTypes)
}
```

- [ ] **Schritt 3: `bodyMeasurementsSection` implementieren**

In `StatsView` (analog zu `weightSection` und anderen `@ViewBuilder`-Properties) einfügen:

```swift
@ViewBuilder
private var bodyMeasurementsSection: some View {
    Section {
        // Typ-Picker
        if measurementTypes.count > 1 {
            Picker("Maß", selection: $selectedMeasurementType) {
                ForEach(measurementTypes) { t in
                    Text(t.name).tag(Optional(t))
                }
            }
            .pickerStyle(.menu)
        }

        let activeType   = selectedMeasurementType ?? measurementTypes.first
        let cutoff       = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let measurements = allBodyMeasurements.filter {
            $0.type?.persistentModelID == activeType?.persistentModelID &&
            $0.date >= cutoff
        }

        if measurements.isEmpty {
            Text("Noch keine Messungen eingetragen.")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            // Letzter Wert
            if let last = measurements.last, let t = activeType {
                HStack {
                    Text("Aktuell")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f \(t.unit)", last.value))
                        .font(.headline)
                }

                // Chart (90 Tage)
                Chart {
                    ForEach(measurements, id: \.date) { m in
                        LineMark(
                            x: .value("Datum", m.date),
                            y: .value(t.unit, m.value)
                        )
                        .foregroundStyle(.purple)
                        PointMark(
                            x: .value("Datum", m.date),
                            y: .value(t.unit, m.value)
                        )
                        .foregroundStyle(.purple)
                    }
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
            }
        }

        Button {
            selectedMeasurementType = selectedMeasurementType ?? measurementTypes.first
            showBodyMeasurementLogger = true
        } label: {
            Label("Messen", systemImage: "ruler")
                .foregroundStyle(.purple)
        }
    } header: {
        Text("Körpermaße")
    }
    .onAppear {
        if selectedMeasurementType == nil {
            selectedMeasurementType = measurementTypes.first
        }
    }
}
```

- [ ] **Schritt 4: BodyMeasurementLoggerSheet hinzufügen**

Am Ende von `StatsView.swift` (nach `WeightLoggerSheet`) einfügen:

```swift
// MARK: - BodyMeasurementLoggerSheet

struct BodyMeasurementLoggerSheet: View {
    let types: [BodyMeasurementType]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var selectedType: BodyMeasurementType?
    @State private var value:  Double = 0
    @State private var date:   Date   = .now

    private var canSave: Bool { selectedType != nil && value > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Maß") {
                    Picker("Maß wählen", selection: $selectedType) {
                        Text("Bitte wählen").tag(Optional<BodyMeasurementType>.none)
                        ForEach(types) { t in
                            Text("\(t.name) (\(t.unit))").tag(Optional(t))
                        }
                    }
                }

                Section("Wert") {
                    HStack {
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                        if let t = selectedType {
                            Text(t.unit).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Datum") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .navigationTitle("Messung eintragen")
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
            .onAppear { selectedType = types.first }
        }
    }

    private func save() {
        guard let t = selectedType else { return }
        let m = BodyMeasurement(type: t, value: value, date: date)
        modelContext.insert(m)
        try? modelContext.save()
        dismiss()
    }
}
```

- [ ] **Schritt 5: iPad-Transfer-Checkpoint (finaler Build)**

Dateien übertragen: `StatsView.swift`. Vollständiger Test:
- Profil → Körpermaße aktivieren → Maß „Taille" (cm) anlegen
- Statistik → Sektion „Körpermaße" erscheint → „Messen" → Wert eintragen
- Chart erscheint nach erstem Eintrag
- Profil → Körpermaße deaktivieren → Sektion verschwindet aus Statistik
- Favoriten: Lebensmittel favorisieren → in FoodSearchSheet unter Favoriten sichtbar
- Rezept favorisieren → in FoodSearchSheet unter Favoriten sichtbar
- Vorlage aus Tagebuch speichern → in Profil sichtbar → im Tagebuch einfügen
- Vorlage manuell im Profil erstellen → im Tagebuch einfügen
