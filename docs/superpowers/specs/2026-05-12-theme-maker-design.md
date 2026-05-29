# Theme-Maker — Design-Dokument
_Datum: 2026-05-12_

## Überblick

Ein Theme-Maker in den Einstellungen (ProfileView) ermöglicht es, die Farben der Calo-App anzupassen. Es gibt zwei Modi: **Normal** (eine Akzentfarbe, Rest wird automatisch abgeleitet) und **Fortgeschritten** (alle Farb-Slots einzeln einstellbar). Farben werden sofort in der ganzen App übernommen. Ein Reset-Button stellt die Standardfarben wieder her.

---

## 1. Einstiegspunkt

- Neuer `NavigationLink("Design anpassen")` in `ProfileView.swift`, in der Sektion „Optionale Features" oder direkt davor als eigene Section.
- Öffnet `ThemeView.swift` (neue Datei).

---

## 2. Architektur — `AppTheme`

**Neue Datei:** `AppTheme.swift`

```
@Observable final class AppTheme {
    // Farb-Slots als Hex-Strings in UserDefaults
    var accentLightHex:  String  // "theme.accent.light"   Default: #34C759
    var accentDarkHex:   String  // "theme.accent.dark"    Default: #34C759
    var proteinHex:      String  // "theme.macro.protein"  Default: #007AFF
    var carbsHex:        String  // "theme.macro.carbs"    Default: #FF9F0A
    var fatHex:          String  // "theme.macro.fat"      Default: #BF5AF2
    var waterHex:        String  // "theme.water"          Default: #5AC8FA
    var warningHex:      String  // "theme.warning"        Default: #FF375F
    var sameForBothModes: Bool   // "theme.sameForBothModes" Default: true

    // Berechnete Color-Properties (lesen aktuellen ColorScheme)
    func accentColor(for scheme: ColorScheme) -> Color
    func accentTextColor(for scheme: ColorScheme) -> Color  // aufgehellt/abgedunkelt, gleicher Ton

    // Convenience-Properties ohne ColorScheme (für einfache Nutzung)
    var accent: Color         // accentColor für aktuellen Scheme
    var protein: Color
    var carbs: Color
    var fat: Color
    var water: Color
    var warning: Color

    // Reset
    func resetToDefaults()
}
```

**Hilfsfunktionen (intern):**
- `Color(hex:)` — Initialisierung aus Hex-String (`#RRGGBB`)
- `Color.toHex()` — Hex-String aus Color
- `Color.lightened(by:)` / `Color.darkened(by:)` — für abgeleitete Textfarben

**Integration in `CaloApp.swift`:**
```swift
@State private var appTheme = AppTheme()
// ...
.environment(appTheme)
```

**Lesen in Views:**
```swift
@Environment(AppTheme.self) private var theme
// Nutzung:
.foregroundStyle(theme.accent)
```

---

## 3. ThemeView — UI

**Neue Datei:** `ThemeView.swift`

### Struktur

```
ThemeView
├── Segmented Picker: "Normal" | "Fortgeschritten"
├── if normal:
│   └── NormalThemeSection
│       ├── Farbswatches (7 Presets + "+" für ColorPicker)
│       ├── Dark/Light-Toggle ("Gleich für Dark & Light")
│       │   └── wenn aus: je ein Swatch-Picker für Light + Dark
│       └── ThemePreviewCard (Live-Vorschau)
├── if advanced:
│   └── AdvancedThemeSection
│       ├── Section "Hauptfarbe": Akzent-Slot + Dark/Light-Toggle
│       ├── Section "Makro-Balken": Protein, Kohlenhydrate, Fett
│       ├── Section "Weitere Farben": Wasser, Warnung
│       └── ThemePreviewCard (Live-Vorschau)
└── Section "Zurücksetzen"
    └── Button "Alle Farben zurücksetzen" (role: .destructive)
        └── confirmationDialog vor dem Reset
```

### Preset-Palette (Normal-Modus)
7 handverlesene Farben, die in Dark und Light Mode gut funktionieren:
`#34C759` (Grün), `#007AFF` (Blau), `#FF9F0A` (Orange), `#FF375F` (Rot/Pink), `#BF5AF2` (Lila), `#5AC8FA` (Hellblau), `#FF6B35` (Koralle)

### Farb-Picker
- Jeder Farb-Slot: Tippen auf den Farbkreis öffnet SwiftUI `ColorPicker` direkt inline (Standard-iOS-Verhalten).
- Im Normal-Modus ersetzt die Wahl einer Preset-Farbe oder Custom-Farbe sofort `accentLightHex` (und `accentDarkHex` wenn `sameForBothModes == true`).

### Dark/Light-Toggle
- `Toggle("Gleich für Dark & Light", isOn: $theme.sameForBothModes)`
- Wenn `false`: zwei Farbwähler erscheinen — einer mit Label „Hell", einer mit „Dunkel".
- Im Normal-Modus gilt der Toggle nur für den Akzent.
- Im Fortgeschritten-Modus gilt er nur für den Akzent-Slot (Makros/Wasser/Warnung sind modusunabhängig — zu viel Komplexität).

### ThemePreviewCard (wiederverwendbare Subview)
Zeigt als Mini-Mockup:
- Kalorien-Ring (Akzentfarbe)
- Drei Makro-Balken (Protein/Carbs/Fett)
- Wasserbalken
- Einen „+ Eintrag"-Button (Akzentfarbe)

Aktualisiert sich sofort bei jeder Farbänderung, da `AppTheme` `@Observable` ist.

### Reset
```swift
Button("Alle Farben zurücksetzen", role: .destructive) {
    showResetConfirmation = true
}
.confirmationDialog(
    "Standardfarben wiederherstellen?",
    isPresented: $showResetConfirmation
) {
    Button("Zurücksetzen", role: .destructive) { theme.resetToDefaults() }
    Button("Abbrechen", role: .cancel) {}
}
```

---

## 4. Integration in bestehende Views

Folgende Views müssen auf `theme.*` umgestellt werden (hardcodierte Farben ersetzen):

| View | Betroffene Farbe(n) |
|---|---|
| `DiaryView.swift` | `CalorieSummaryCard` Ring → `theme.accent`; Makro-Balken → `theme.protein/.carbs/.fat`; WaterCard → `theme.water` |
| `FoodSearchSheet.swift` | Buttons, Chips → `theme.accent` |
| `SearchView.swift` | Buttons → `theme.accent` |
| `StatsView.swift` | Kalorien-Chart-Balken → `theme.accent`; Gewichts-Chart → `theme.accent` |
| `ProfileView.swift` | Kalorienzahl (`.foregroundStyle(.green)`) → `theme.accent` |
| `RecipesView.swift` | Buttons → `theme.accent` |
| `RecipeEditorView.swift` | Buttons → `theme.accent` |
| `OnboardingView.swift` | Akzent-Elemente → `theme.accent` |

**Vorgehen:** `@Environment(AppTheme.self) private var theme` in jede betroffene View; alle `.foregroundStyle(.green)` / `.green` durch `theme.accent` ersetzen, Makro-Farben entsprechend.

---

## 5. Dateiübersicht (neu/geändert)

| Datei | Änderung |
|---|---|
| `AppTheme.swift` | **Neu** — Observable Klasse, alle Farb-Slots, Reset |
| `ThemeView.swift` | **Neu** — Theme-Maker UI (Normal + Fortgeschritten + Vorschau + Reset) |
| `CaloApp.swift` | `AppTheme` instanziieren, per `.environment()` einreichen |
| `ProfileView.swift` | NavigationLink „Design anpassen" + Kalorienzahl-Farbe auf `theme.accent` |
| `DiaryView.swift` | Ring → `theme.accent`; Makros → `theme.protein/.carbs/.fat`; Wasser → `theme.water` |
| `FoodSearchSheet.swift` | Buttons, Chips → `theme.accent` |
| `SearchView.swift` | Buttons → `theme.accent` |
| `StatsView.swift` | Chart-Balken → `theme.accent` |
| `RecipesView.swift` | Buttons → `theme.accent` |
| `RecipeEditorView.swift` | Buttons → `theme.accent` |
| `OnboardingView.swift` | Akzent-Elemente → `theme.accent` |

---

## 6. Nicht im Scope

- HealthKit-Integration
- BMI-Balken-Farben (blau/grün/orange/rot sind semantisch fest an BMI-Kategorien gebunden — kein Theme)
- Dark/Light-Toggle für Makros/Wasser/Warnung (zu komplex, zu wenig Mehrwert)
- Theme-Export/-Import
