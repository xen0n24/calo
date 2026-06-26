# Calo – CLAUDE.md

## Projektübersicht

Native iOS-Kalorientracking-App. Hobby-Projekt, Distribution direkt über Swift Playgrounds auf iPad/iPhone (kein App Store). Code wird auf **Windows** via Claude Code geschrieben, Dateien liegen in **iCloud Drive**, Build läuft auf **iPad** in Swift Playgrounds.

**Entwickler:** FiSi-Azubi, IT-Hintergrund, kein Swift-Profi — Swift-spezifische Konzepte kurz erklären wenn nicht offensichtlich.

## Setup

- **Pfad:** `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\`
- **Plattform:** iOS/iPadOS 26, Swift 6, SwiftUI
- **Architektur:** MV (Model-View) — keine ViewModels
- **Persistierung:** SwiftData
- **Sprache UI:** Deutsch. Code-Bezeichner: Englisch.
- **Ordnerstruktur:** `Core/` (Logik, Modelle, Services) und `Views/` (SwiftUI-Views). `Package.swift` nutzt `path: "."` — SPM findet `.swift`-Dateien rekursiv.
- **Sync:** iCloud Drive (iCloud for Windows). Änderungen werden manuell auf iPad übertragen, weil iCloud-Sync unzuverlässig ist.

## Workflow-Regeln

1. **Am Ende jeder Antwort:** Liste aller geänderten/neuen Dateien ausgeben (für manuellen iPad-Transfer).
2. **Am Ende jeder Antwort:** Kurze Stichpunktliste was in der App jetzt geht.
3. **Phasenweise arbeiten** – nach jedem Block auf Bestätigung warten ("klappt").
4. **Mehrere Features auf einmal** wenn der User "nächste steps" sagt.

## Swift-Playgrounds-Limits (KRITISCH)

- ✅ **`Info.plist` wird im CI-Workflow generiert** → `NSCameraUsageDescription` und andere Keys direkt im Python-Dict in `.github/workflows/build.yml` eintragen
- ❌ **Kein verschachteltes `List` in `List`** → crasht ohne Fehlermeldung → immer `ForEach` direkt in äußerem `List`
- ❌ **`@retroactive` nur für fremde Module** → `@Model`-Typen sind bereits `Identifiable`, keine Extension nötig
- ❌ **`ForEach` mit Index-`id`** + `.onDelete` crasht → immer `Identifiable`-Struct verwenden
- ❌ **`Text(...) + Text(...)`** funktioniert nicht nach `.font()`/`.foregroundStyle()` → `HStack` mit zwei `Text`-Views
- ✅ **`switch`-Ausdrücke** funktionieren in Swift 6, aber Integer-Literale explizit als `Double` schreiben (z.B. `0.0` statt `0`)

## SwiftData-Muster

### Dynamische Date-Filter
Kind-View mit eigenem `init` verwenden, damit `#Predicate` zur Init-Zeit gesetzt wird:
```swift
struct DiaryDateContent: View {
    init(date: Date, ...) {
        let start = Calendar.current.startOfDay(for: date)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        _entries = Query(filter: #Predicate<DiaryEntry> { e in e.date >= start && e.date < end }, ...)
    }
}
```

### Schema in CaloApp.swift
Alle neuen `@Model`-Typen hier eintragen:
```swift
container = try ModelContainer(for:
    Food.self, Nutrition.self, DiaryEntry.self, WeightEntry.self,
    UserProfile.self, Recipe.self, RecipeIngredient.self, WaterLog.self
)
```

## Datenmodell (Models.swift)

| Modell | Zweck |
|---|---|
| `Food` | Lebensmittel (seed / openFoodFacts / custom / recipe) |
| `Nutrition` | Nährwerte pro 100 g (kcal, protein, carbs, fat + optionale Mikros) |
| `DiaryEntry` | Tagebucheintrag (date, meal, food, grams, loggedAt) |
| `WeightEntry` | Gewichtseintrag (date, weightKg) |
| `UserProfile` | Einziges Profil-Objekt (Ziel, TDEE, Kalorienziel, MacroSplit, waterGoalMl) |
| `Recipe` | Rezept mit Zutaten und Gesamtgewicht |
| `RecipeIngredient` | Zutat in einem Rezept (food, grams) |
| `WaterLog` | Tägliches Wassertrinken (date = startOfDay, mlConsumed) |

`MacroSplit` ist ein `Codable`-Struct (kein eigenes `@Model`), eingebettet in `UserProfile`.

## Alle Dateien (Stand 2026-06-04)

### Core/ (Logik, Daten, Services)

| Datei | Inhalt |
|---|---|
| `Core/Models.swift` | Alle SwiftData-Modelle + Enums + Recipe-Extensions; `BodyMeasurementType` hat `groupName: String?` |
| `Core/TDEECalculator.swift` | Pure Functions: age, bmr, tdee, calorieTarget |
| `Core/AdaptiveCalorieEngine.swift` | Adaptiver Algorithmus (14-Tage-Fenster, ±100 kcal/0.1 kg) |
| `Core/OpenFoodFactsClient.swift` | OFF API v2: product(barcode:) + search(query:) |
| `Core/FoodSearch.swift` | Lokale Lebensmittelsuche-Logik |
| `Core/SeedFoodImporter.swift` | Importiert `seed-foods-de.json` beim ersten Start |
| `Core/NotificationManager.swift` | UNUserNotificationCenter: tägliche + wöchentliche Erinnerungen |
| `Core/HapticManager.swift` | UIImpactFeedbackGenerator-Wrapper |
| `Core/AppTheme.swift` | `@Observable @MainActor AppTheme`-Klasse: alle Farb-Slots als Hex-Strings in UserDefaults, Color-Extensions (`init(hex:)`, `toHex()`), `resetToDefaults()` |
| `Core/BackupManager.swift` | Backup/Restore-Logik |
| `Core/PhotoMealRecognizer.swift` | Foto-basierte Mahlzeiterkennung (Vision/ML) |

### Views/ (SwiftUI)

| Datei | Inhalt |
|---|---|
| `Views/CaloApp.swift` | @main, ModelContainer |
| `Views/ContentView.swift` | Routing: Onboarding ↔ MainTabView |
| `Views/MainTabView.swift` | TabView (Tagebuch, Suche, Statistik, Profil) + Badge auf Tagebuch-Tab |
| `Views/OnboardingView.swift` | 8-Schritt-Onboarding, speichert UserProfile + erstes WeightEntry |
| `Views/DiaryView.swift` | Tagebuch: CalorieSummaryCard (Ring-Animation, Kalorien-Übertrag), WaterCard, MealSectionCard, EntryRow, DiaryEntryEditSheet |
| `Views/FoodSearchSheet.swift` | Sheet aus Tagebuch „+": Chips für zuletzt genutzte Foods, AmountInputView (TextField + Schnellschritte), Suche, Barcode, Rezepte |
| `Views/SearchView.swift` | Such-Tab: Foods + Rezepte, Vorschläge, Online-Suche, FoodDetailSheet |
| `Views/CustomFoodSheet.swift` | Eigenes Lebensmittel erstellen oder bearbeiten |
| `Views/BarcodeScannerView.swift` | VisionKit DataScannerViewController-Wrapper |
| `Views/RecipesView.swift` | RecipeRow, RecipeDetailSheet (mit Tagebuch-Log) |
| `Views/RecipeEditorView.swift` | Rezept-Editor + IngredientPickerSheet |
| `Views/StatsView.swift` | Streak, Gewicht-Chart, Kalorien-Chart, TDEE, Adaptives Ziel, Gewichtsprognose, Körpermaße (Separat/Kombiniert/Gruppen), WeightLoggerSheet, BodyMeasurementLoggerSheet, GroupManagerSheet |
| `Views/ProfileView.swift` | Profil, BMI-Farbbalken (BMIScaleRow), TDEE, Benachrichtigungen, Reset |
| `Views/ProfileEditSheet.swift` | Ziel / Aktivität / Rate / Kalorienziel / Wasserziel / MacroSplit bearbeiten |
| `Views/OptionalFeaturesView.swift` | Feature-Flags: Körpermaße, Foto-Erkennung, Kalorien-Übertrag |
| `Views/ThemeView.swift` | Theme-Maker: `ThemeView` (NavigationLink-Ziel), `NormalThemeSection` (Swatches + ColorPicker + Dark/Light-Toggle), `AdvancedThemeSection` (Gruppen), `ThemePreviewCard` (Live-Vorschau) |
| `Views/MealTemplateEditorView.swift` | Mahlzeit-Vorlagen Editor |
| `Views/PhotoMealSheet.swift` | Foto-Mahlzeit-Sheet (Kamera + Erkennung) |
| `Views/FlowLayout.swift` | Flexibles Flow-Layout für Chips/Tags |
| `Views/MyApp.swift` | Stub (leer, ignorieren) |

### Root

| Datei | Inhalt |
|---|---|
| `Package.swift` | SPM-Konfiguration (`path: "."`, findet Swift-Dateien rekursiv) |
| `seed-foods-de.json` | Seed-Datenbank für `SeedFoodImporter` |

## Features (vollständig implementiert)

- Onboarding (Geschlecht, Alter, Größe, Gewicht, Aktivität, Ziel)
- Tagebuch mit Datumsnavigation (auch Zukunft), Kalorien-Ring (animiert), Makro-Fortschrittsbalken
- Kalorien-Übertrag: Vortags-Deficit/-Überschuss auf Tagesziel anrechnen (±500 kcal Deckel, optional)
- Wassertracking mit Fortschrittsbalken und Schnellbuttons
- Einträge kopieren (von gestern / von letzter Woche)
- Lebensmittelsuche: lokal + Open Food Facts + Barcode-Scanner
- Zuletzt genutzte Foods als horizontale Chip-Leiste (FoodSearchSheet)
- Lebensmittelmenge: Rad-Picker (5–2000 in 5er-Schritten) + g/ml-Toggle (auto per Food.unit, manuell umschaltbar)
- Eigene Lebensmittel erstellen und bearbeiten
- Lebensmittel löschen (nur `source == .custom`)
- Diary-Einträge nachträglich bearbeiten (Gramm, Mahlzeit, Datum)
- Rezepte mit gramm-basierter Skalierung
- Statistiken: Gewichtsverlauf (90 Tage), Kalorienbalken (14 Tage), Streak, Gewichtsprognose
- Adaptiver Kalorienziel-Algorithmus (MacroFactor-Stil, 14-Tage-Fenster)
- Profil bearbeiten ohne Reset (Ziel, Aktivität, Kalorienziel, Makros, Wasserziel)
- BMI-Farbbalken mit Pfeilmarkierung (BMIScaleRow in ProfileView)
- Lokale Benachrichtigungen (tägliches Logging, wöchentliches Wiegen)
- Mikronährstoffe (Ballaststoffe, Zucker, Salz, ges. Fette) im Tagebuch
- Körpermaße: Maßtypen anlegen, Messungen eintragen, Separat- oder Kombiniert-Chart, Gruppen (z. B. Oberkörper/Unterkörper) mit Zuordnung im GroupManagerSheet
- Badge auf Tagebuch-Tab wenn heute nichts geloggt
- **Theme-Maker** (Profil → „Design anpassen"): Normal-Modus (Akzentfarbe per Swatch oder freiem ColorPicker, Dark/Light-Toggle) und Fortgeschritten-Modus (Akzent, Protein, Kohlenhydrate, Fett, Wasser, Warnung, Körpermaße einzeln einstellbar), Live-Vorschau, Reset auf Standard

## Swift-Patterns die funktionieren / nicht funktionieren

- ❌ **`let` inside `@ChartContentBuilder` ForEach** → Kompilerfehler. Daten immer vor `Chart { }` als Array vorberechnen, z. B. mit einer Hilfsfunktion die ein `[MyStruct]` zurückgibt.
- ❌ **Ternary mit `.secondary` + `.orange`/`.green`** → Typ-Konflikt (HierarchicalShapeStyle vs Color). Fix: immer `Color.secondary`, `Color.orange`, `Color.green` explizit schreiben.
- ❌ **`sheet(isPresented:)` mit sich änderndem Inhalt** → SwiftUI cached den Closure, `initialType` bleibt beim alten Wert. Fix: `sheet(item:)` mit `Identifiable`-Wrapper (`id = UUID()`) verwenden.
- ✅ **`_state = State(initialValue:)` im `init`** → zuverlässige Alternative zu `.onAppear` für @State-Vorauswahl.
- ✅ **`ForEach(data)` mit SwiftData `@Model`** → `@Model` ist automatisch `Identifiable`, kein `id:` nötig.
- ✅ **`@Observable`-Klasse mit UserDefaults** → Stored property mit `didSet { UserDefaults.standard.set(...) }` und Default-Wert aus `UserDefaults.standard.string(forKey:) ?? "..."`. Observation funktioniert, Persistenz automatisch.
- ✅ **Binding aus `@Observable`-Klasse in View** → `@Bindable var theme = theme` am Anfang von `body` (lokale Variable), danach `$theme.property` nutzbar.
- ✅ **`ReferenceWritableKeyPath` für `@Observable`-Klassen** → `hexBinding(_ keyPath: ReferenceWritableKeyPath<AppTheme, String>)` funktioniert für generische ColorPicker-Bindings.
- ❌ **Ternary mit `theme.accent` und `.secondary`** → Typ-Konflikt. Fix: `Color.secondary` explizit schreiben.

## Bekannte Konventionen

- `NumericStepperView` ist in `OnboardingView.swift` definiert — wiederverwendbar
- `FoodResultRow` ist in `FoodSearchSheet.swift` definiert — in SearchView importiert
- `WheelAmountPicker` ist in `FoodSearchSheet.swift` definiert — Rad-Picker für Gramm/ml-Eingabe mit g/ml-Toggle
- Zwei-Rad-Picker in `amountView`: links Portionsname (Picker), rechts Anzahl (1–20) oder Gramm (5–2000) — kein separates Chip-UI
- `RecentFoodChip` ist in `FoodSearchSheet.swift` definiert — horizontale Chip-Darstellung
- `MeasurementLogRequest` ist in `StatsView.swift` definiert — Identifiable-Wrapper für sheet(item:)
- `MeasurementPoint` ist in `StatsView.swift` definiert — flache Datenstruktur für kombinierten Chart
- `BMIScaleRow` ist in `ProfileView.swift` definiert — visueller BMI-Balken mit GeometryReader
- Rezept-Logging: Snapshot-`Food` mit `source: .recipe` pro Log-Vorgang erstellen
- Barcode-Scanner: `DataScannerViewController.isSupported` vor Anzeige prüfen
- Online-Suche: 550 ms Debounce, Task cancellable
- `@AppStorage` für Notification-Settings und Feature-Flags (kein SwiftData nötig)
- Körpermaße komplett in StatsView — nichts davon in ProfileView
- `AppTheme` wird in `CaloApp.swift` als `@State private var appTheme = AppTheme()` instanziiert und per `.environment(appTheme)` weitergegeben — jede View liest `@Environment(AppTheme.self) private var theme`
- Theme-Farb-Slots: `accent` (Light+Dark), `protein`, `carbs`, `fat`, `water`, `warning`, `bodyMeasurement` — alle als Hex-Strings in UserDefaults
- BMI-Balken-Farben in `BMIScaleRow` bleiben fix (semantisch an BMI-Kategorien gebunden, kein Theme)
- Mikronährstoff-Balken in `DiaryView` bleiben fix lila (zu selten sichtbar)

## Potenzielle nächste Features

- HealthKit (Gewicht importieren / Kalorien exportieren) — Capability in Playgrounds-UI nötig
- App-Icon und visuelles Polishing

