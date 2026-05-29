# Design: Favoriten, Meal Templates, Body Measurements

**Datum:** 2026-05-04  
**Projekt:** Calo – iOS Kalorientracking-App  
**Status:** Genehmigt

---

## 1. Favoriten

### Datenmodell
- `Food` bekommt `var isFavorite: Bool = false`
- `Recipe` bekommt `var isFavorite: Bool = false`
- Keine separaten Models nötig — Flag direkt auf den bestehenden Modellen

### UI
- **FoodSearchSheet:** Neuer Tab „Favoriten" ganz links (vor „Vorschläge")
  - Sektion 1: Favorisierte Lebensmittel (`Food` where `isFavorite == true`)
  - Sektion 2: Favorisierte Rezepte (`Recipe` where `isFavorite == true`)
  - Leere Zustände wenn keine Favoriten vorhanden
- **Favorisieren:** Swipe-Action mit Herz-Symbol in allen Listen wo Foods/Rezepte auftauchen:
  - FoodSearchSheet (Vorschläge, Suche-Ergebnisse)
  - SearchView
  - RecipesView

### Queries
- `@Query(filter: #Predicate<Food> { $0.isFavorite })` für Favoriten-Tab
- `@Query(filter: #Predicate<Recipe> { $0.isFavorite })` für Rezept-Favoriten

---

## 2. Meal Templates

### Datenmodell

```swift
@Model final class MealTemplate {
    var id: UUID
    var name: String
    var mealType: MealType          // Standard-Mahlzeit für dieses Template
    @Relationship(deleteRule: .cascade) var entries: [TemplateEntry]
    var createdAt: Date
}

@Model final class TemplateEntry {
    var food: Food?                 // Optional: falls Food gelöscht wird
    var grams: Double
    var template: MealTemplate?
}
```

### Template erstellen — Weg 1: Aus Tagebuch
- Jede Mahlzeit-Section in `DiaryView` bekommt einen „Als Vorlage speichern"-Button
- Tippt man drauf: Sheet öffnet sich zur Namenseingabe
- Alle aktuellen `DiaryEntry`s dieser Mahlzeit werden als `TemplateEntry`s gespeichert
- `mealType` wird von der Section übernommen

### Template erstellen — Weg 2: Manueller Editor
- In `ProfileView` neue Sektion „Vorlagen" (Liste aller Templates + „Neue Vorlage"-Button)
- Editor (`MealTemplateEditorView`) ähnlich `RecipeEditorView`:
  - Name eingeben
  - Standard-Mahlzeit wählen (Picker)
  - Zutaten hinzufügen (Food-Picker mit Gramm)
  - Löschen einzelner Einträge

### Template anwenden
- Jede Mahlzeit-Section in `DiaryView` bekommt ein Menü beim „+"-Button:
  - „Lebensmittel hinzufügen" → öffnet FoodSearchSheet (wie bisher)
  - „Vorlage einfügen" → öffnet Sheet mit Liste aller Templates
- Nach Auswahl: alle `TemplateEntry`s werden als einzelne `DiaryEntry`s auf den aktuellen Tag + gewählte Mahlzeit geloggt
- Einträge werden unabhängig voneinander erstellt (kein Block/Gruppe)

### Template verwalten
- In `ProfileView` → Sektion „Vorlagen": Swipe-to-Delete, Tap zum Bearbeiten

---

## 3. Body Measurements

### Feature-Toggle
- `@AppStorage("feature.bodyMeasurements.enabled")` in `ProfileView`
- Toggle „Körpermaße aktivieren" in einer neuen Sektion „Optionale Features" in ProfileView
- Wenn deaktiviert: keine sichtbaren UI-Elemente außer dem Toggle selbst

### Datenmodell

```swift
@Model final class BodyMeasurementType {
    var id: UUID
    var name: String           // z.B. "Taille"
    var unit: String           // z.B. "cm"
    var sortOrder: Int         // für benutzerdefinierte Reihenfolge
    // Cascade: Messungen werden mitgelöscht wenn der Typ gelöscht wird
    @Relationship(deleteRule: .cascade, inverse: \BodyMeasurement.type)
    var measurements: [BodyMeasurement] = []
}

@Model final class BodyMeasurement {
    var type: BodyMeasurementType?
    var value: Double
    var date: Date
}
```

### Typen verwalten (ProfileView)
- Nur sichtbar wenn Feature aktiv
- Neue Sektion „Körpermaße" in ProfileView mit Liste der konfigurierten Typen
- „+" zum Hinzufügen: Name + Einheit eingeben (z.B. „Taille", „cm")
- Swipe-to-Delete (löscht auch alle Messungen dieses Typs via `deleteRule: .cascade`)

### Messungen erfassen (StatsView)
- Nur sichtbar wenn Feature aktiv
- Neue Sektion „Körpermaße" nach dem Gewichts-Chart
- Picker: welches Maß wird angezeigt
- Linien-Chart (90 Tage, analog Gewichts-Chart)
- „Messen"-Button öffnet `BodyMeasurementLoggerSheet`:
  - Picker für Messtyp
  - Nummerisches Eingabefeld
  - Datum (default: heute)

---

## 4. Schema-Änderungen (CaloApp.swift)

Neue Modelle müssen in den `ModelContainer` eingetragen werden:

```swift
container = try ModelContainer(for:
    Food.self, Nutrition.self, DiaryEntry.self, WeightEntry.self,
    UserProfile.self, Recipe.self, RecipeIngredient.self, WaterLog.self,
    MealTemplate.self, TemplateEntry.self,
    BodyMeasurementType.self, BodyMeasurement.self
)
```

---

## 5. Dateien (neu/geändert)

| Datei | Änderung |
|---|---|
| `Models.swift` | `isFavorite` auf Food + Recipe; neue Models: MealTemplate, TemplateEntry, BodyMeasurementType, BodyMeasurement |
| `CaloApp.swift` | Neue Models in ModelContainer |
| `FoodSearchSheet.swift` | Neuer „Favoriten"-Tab |
| `SearchView.swift` | Swipe-to-Favorite auf Foods |
| `RecipesView.swift` | Swipe-to-Favorite auf Rezepte |
| `DiaryView.swift` | „Als Vorlage speichern" + „Vorlage einfügen"-Menü |
| `ProfileView.swift` | Sektion „Vorlagen", Sektion „Körpermaße", Toggle „Optionale Features" |
| `MealTemplateEditorView.swift` | Neu: manueller Template-Editor |
| `StatsView.swift` | Sektion „Körpermaße" mit Chart + Logger-Sheet |
