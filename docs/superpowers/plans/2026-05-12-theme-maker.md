# Theme-Maker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Einen Theme-Maker in den Einstellungen hinzufügen, der App-Farben global veränderbar macht — Normal-Modus (eine Akzentfarbe, Rest wird abgeleitet) und Fortgeschritten-Modus (alle Farb-Slots einzeln).

**Architecture:** Eine `@Observable @MainActor`-Klasse `AppTheme` speichert alle Farben als Hex-Strings in UserDefaults (via `didSet`). Sie wird in `CaloApp.swift` instanziiert und per `.environment(appTheme)` in den ganzen View-Baum gereicht. Views lesen `@Environment(AppTheme.self) private var theme` und referenzieren `theme.accent`, `theme.protein` usw. direkt.

**Tech Stack:** Swift 6, SwiftUI, iOS 26, `@Observable` (Observation framework), UserDefaults, SwiftUI `ColorPicker`

**Hinweis zu Tests:** Swift Playgrounds hat kein Test-Framework. Jede Aufgabe endet mit einem manuellen Build-Checkpoint (Sync zu iPad → Build in Swift Playgrounds → Verhalten prüfen). Zwischendurch kann Code-Review die Logik absichern.

---

## Dateien-Übersicht

| Datei | Aktion | Inhalt |
|---|---|---|
| `AppTheme.swift` | **Neu** | `@Observable AppTheme`-Klasse + `Color`-Extensions |
| `ThemeView.swift` | **Neu** | Komplette Theme-Maker-UI (Normal + Fortgeschritten + Vorschau + Reset) |
| `CaloApp.swift` | Ändern | `AppTheme` instanziieren + `.environment(appTheme)` |
| `ProfileView.swift` | Ändern | NavigationLink „Design anpassen" + Kalorienzahl auf `theme.accent` |
| `DiaryView.swift` | Ändern | Ring, Makros, Wasser, Buttons auf `theme.*` |
| `FoodSearchSheet.swift` | Ändern | Buttons/Chips auf `theme.accent` |
| `SearchView.swift` | Ändern | Buttons auf `theme.accent` |
| `StatsView.swift` | Ändern | Chart-Balken auf `theme.accent` |
| `RecipesView.swift` | Ändern | Buttons auf `theme.accent` |
| `RecipeEditorView.swift` | Ändern | Buttons auf `theme.accent` |
| `OnboardingView.swift` | Ändern | Akzent-Elemente auf `theme.accent` |

---

## Task 1: AppTheme.swift — Kern-Modell

**Files:**
- Create: `AppTheme.swift`

- [ ] **Schritt 1: Datei erstellen**

Erstelle `AppTheme.swift` mit folgendem vollständigen Inhalt:

```swift
import SwiftUI
import Observation

// MARK: - Color Extensions

extension Color {
    /// Initialisierung aus einem Hex-String wie "#34C759" oder "34C759"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255.0
        let g = Double((int & 0x00FF00) >> 8)  / 255.0
        let b = Double(int  & 0x0000FF)         / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Gibt den Hex-String dieser Farbe zurück (ohne Transparenz)
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - AppTheme

@Observable @MainActor final class AppTheme {

    // MARK: Farb-Slots (als Hex-Strings in UserDefaults)

    var accentLightHex: String = UserDefaults.standard.string(forKey: "theme.accent.light") ?? "#34C759" {
        didSet { UserDefaults.standard.set(accentLightHex, forKey: "theme.accent.light") }
    }

    var accentDarkHex: String = UserDefaults.standard.string(forKey: "theme.accent.dark") ?? "#34C759" {
        didSet { UserDefaults.standard.set(accentDarkHex, forKey: "theme.accent.dark") }
    }

    var proteinHex: String = UserDefaults.standard.string(forKey: "theme.macro.protein") ?? "#007AFF" {
        didSet { UserDefaults.standard.set(proteinHex, forKey: "theme.macro.protein") }
    }

    var carbsHex: String = UserDefaults.standard.string(forKey: "theme.macro.carbs") ?? "#FF9F0A" {
        didSet { UserDefaults.standard.set(carbsHex, forKey: "theme.macro.carbs") }
    }

    var fatHex: String = UserDefaults.standard.string(forKey: "theme.macro.fat") ?? "#FFCC00" {
        didSet { UserDefaults.standard.set(fatHex, forKey: "theme.macro.fat") }
    }

    var waterHex: String = UserDefaults.standard.string(forKey: "theme.water") ?? "#5AC8FA" {
        didSet { UserDefaults.standard.set(waterHex, forKey: "theme.water") }
    }

    var warningHex: String = UserDefaults.standard.string(forKey: "theme.warning") ?? "#FF375F" {
        didSet { UserDefaults.standard.set(warningHex, forKey: "theme.warning") }
    }

    var sameForBothModes: Bool = (UserDefaults.standard.object(forKey: "theme.sameForBothModes") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(sameForBothModes, forKey: "theme.sameForBothModes") }
    }

    // MARK: Berechnete Color-Properties

    /// Akzentfarbe passend zum ColorScheme (wenn sameForBothModes == false)
    func accentColor(for scheme: ColorScheme) -> Color {
        if sameForBothModes { return Color(hex: accentLightHex) }
        return scheme == .dark ? Color(hex: accentDarkHex) : Color(hex: accentLightHex)
    }

    /// Convenience: immer die Light-Variante (ausreichend wenn sameForBothModes == true)
    var accent:  Color { Color(hex: accentLightHex) }
    var protein: Color { Color(hex: proteinHex) }
    var carbs:   Color { Color(hex: carbsHex) }
    var fat:     Color { Color(hex: fatHex) }
    var water:   Color { Color(hex: waterHex) }
    var warning: Color { Color(hex: warningHex) }

    // MARK: Reset

    func resetToDefaults() {
        accentLightHex  = "#34C759"
        accentDarkHex   = "#34C759"
        proteinHex      = "#007AFF"
        carbsHex        = "#FF9F0A"
        fatHex          = "#FFCC00"
        waterHex        = "#5AC8FA"
        warningHex      = "#FF375F"
        sameForBothModes = true
    }
}
```

- [ ] **Schritt 2: Kurz-Review**

Prüfe:
- Alle 7 Farb-Slots haben einen `didSet` der in UserDefaults schreibt
- `resetToDefaults()` setzt alle Werte zurück
- `Color(hex:)` und `toHex()` sind vollständig implementiert

---

## Task 2: ThemePreviewCard — Live-Vorschau

**Files:**
- Create: `ThemeView.swift` (Datei anlegen, wird in Tasks 3–5 weitergebaut)

- [ ] **Schritt 1: ThemeView.swift anlegen mit ThemePreviewCard**

```swift
import SwiftUI

// MARK: - ThemePreviewCard

/// Zeigt eine Mini-Vorschau der aktuellen Theme-Farben.
/// Aktualisiert sich automatisch wenn AppTheme sich ändert.
struct ThemePreviewCard: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { theme.accentColor(for: colorScheme) }

    var body: some View {
        VStack(spacing: 10) {
            // Kalorien-Ring + Makro-Balken
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(accent,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("1850")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                        Text("kcal")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)

                VStack(spacing: 6) {
                    previewBar(color: theme.protein, fraction: 0.70, label: "Protein")
                    previewBar(color: theme.carbs,   fraction: 0.55, label: "Kohlenhydr.")
                    previewBar(color: theme.fat,     fraction: 0.40, label: "Fett")
                    previewBar(color: theme.water,   fraction: 0.60, label: "Wasser")
                }
            }

            // Button-Vorschau
            HStack {
                Label("Eintrag hinzufügen", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text("2100 kcal Ziel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func previewBar(color: Color, fraction: Double, label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.75))
                        .frame(width: geo.size.width * fraction, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}
```

- [ ] **Schritt 2: Review**

Prüfe: Alle `theme.*`-Properties existieren in `AppTheme` (aus Task 1). `accent` nutzt `accentColor(for: colorScheme)` für korrekte Dark/Light-Unterstützung.

---

## Task 3: NormalThemeSection

**Files:**
- Modify: `ThemeView.swift` (unter `ThemePreviewCard` anhängen)

- [ ] **Schritt 1: NormalThemeSection an ThemeView.swift anhängen**

```swift
// MARK: - NormalThemeSection

struct NormalThemeSection: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private let presets = [
        "#34C759", "#007AFF", "#FF9F0A", "#FF375F",
        "#BF5AF2", "#5AC8FA", "#FF6B35"
    ]

    var body: some View {
        @Bindable var theme = theme

        VStack(alignment: .leading, spacing: 16) {

            // Farbwahl-Zeile
            VStack(alignment: .leading, spacing: 10) {
                Text("Akzentfarbe")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { hex in
                        swatchButton(hex: hex)
                    }
                    // Freier Farbwähler als letzter Swatch
                    ColorPicker("Eigene Farbe",
                                selection: customBinding,
                                supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                }
            }

            // Dark/Light Toggle
            Toggle("Gleich für Dark & Light Mode", isOn: $theme.sameForBothModes)
                .onChange(of: theme.sameForBothModes) { _, same in
                    if same { theme.accentDarkHex = theme.accentLightHex }
                }

            // Wenn getrennte Modi: zwei Picker zeigen
            if !theme.sameForBothModes {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hell-Modus").font(.caption).foregroundStyle(.secondary)
                        ColorPicker("Hell",
                                    selection: hexBinding(\.accentLightHex),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dunkel-Modus").font(.caption).foregroundStyle(.secondary)
                        ColorPicker("Dunkel",
                                    selection: hexBinding(\.accentDarkHex),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Hilfsmethoden

    @ViewBuilder
    private func swatchButton(hex: String) -> some View {
        let isSelected = theme.accentLightHex == hex
        Button { selectAccent(hex) } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .shadow(color: isSelected ? Color(hex: hex).opacity(0.6) : .clear,
                        radius: 4)
        }
        .buttonStyle(.plain)
    }

    private func selectAccent(_ hex: String) {
        theme.accentLightHex = hex
        if theme.sameForBothModes { theme.accentDarkHex = hex }
    }

    /// Binding<Color> aus einem Hex-String-KeyPath auf AppTheme
    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme[keyPath: keyPath]) },
            set: { theme[keyPath: keyPath] = $0.toHex() }
        )
    }

    /// Binding für den freien Farbwähler (schreibt immer in accentLightHex + ggf. accentDarkHex)
    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: theme.accentLightHex) },
            set: { newColor in
                let hex = newColor.toHex()
                theme.accentLightHex = hex
                if theme.sameForBothModes { theme.accentDarkHex = hex }
            }
        )
    }
}
```

- [ ] **Schritt 2: Review**

Prüfe:
- `@Bindable var theme = theme` erlaubt `$theme.sameForBothModes` als Binding
- `hexBinding(_:)` nutzt `ReferenceWritableKeyPath` (korrekt für `class`)
- Der `customBinding` schreibt in beide Hex-Slots wenn `sameForBothModes == true`

---

## Task 4: AdvancedThemeSection

**Files:**
- Modify: `ThemeView.swift` (unter `NormalThemeSection` anhängen)

- [ ] **Schritt 1: AdvancedThemeSection anhängen**

```swift
// MARK: - AdvancedThemeSection

struct AdvancedThemeSection: View {
    @Environment(AppTheme.self) private var theme

    var body: some View {
        @Bindable var theme = theme

        VStack(spacing: 0) {

            // --- Hauptfarbe ---
            sectionHeader("Hauptfarbe")
            colorRow(label: "Akzent (Ring, Buttons, Kalorienzahl)",
                     keyPath: \.accentLightHex)

            Toggle("Gleich für Dark & Light Mode", isOn: $theme.sameForBothModes)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: theme.sameForBothModes) { _, same in
                    if same { theme.accentDarkHex = theme.accentLightHex }
                }

            if !theme.sameForBothModes {
                colorRow(label: "Akzent – Dunkel-Modus", keyPath: \.accentDarkHex)
            }

            Divider().padding(.vertical, 8)

            // --- Makro-Balken ---
            sectionHeader("Makro-Balken")
            colorRow(label: "Protein",        keyPath: \.proteinHex)
            colorRow(label: "Kohlenhydrate",  keyPath: \.carbsHex)
            colorRow(label: "Fett",           keyPath: \.fatHex)

            Divider().padding(.vertical, 8)

            // --- Weitere Farben ---
            sectionHeader("Weitere Farben")
            colorRow(label: "Wasser",             keyPath: \.waterHex)
            colorRow(label: "Warnung / Überschuss", keyPath: \.warningHex)
        }
    }

    // MARK: - Hilfsmethoden

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private func colorRow(label: String,
                          keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            ColorPicker("",
                        selection: hexBinding(keyPath),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme[keyPath: keyPath]) },
            set: { theme[keyPath: keyPath] = $0.toHex() }
        )
    }
}
```

- [ ] **Schritt 2: Review**

Prüfe: Alle `keyPath`-Argumente entsprechen Property-Namen in `AppTheme` (Task 1). Das Divider-Layout trennt die drei Gruppen sauber.

---

## Task 5: ThemeView — Haupt-Screen

**Files:**
- Modify: `ThemeView.swift` (am Ende der Datei anhängen — schließt die Datei ab)

- [ ] **Schritt 1: ThemeView (Root) anhängen**

```swift
// MARK: - ThemeView

struct ThemeView: View {
    @Environment(AppTheme.self) private var theme

    @State private var mode: ThemeMode = .normal
    @State private var showResetConfirmation = false

    enum ThemeMode: String, CaseIterable {
        case normal       = "Normal"
        case advanced     = "Fortgeschritten"
    }

    var body: some View {
        List {
            // Modus-Auswahl
            Section {
                Picker("Modus", selection: $mode) {
                    ForEach(ThemeMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Normal oder Fortgeschritten
            Section {
                if mode == .normal {
                    NormalThemeSection()
                        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                } else {
                    AdvancedThemeSection()
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }

            // Live-Vorschau
            Section("Vorschau") {
                ThemePreviewCard()
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Reset
            Section {
                Button("Alle Farben zurücksetzen", role: .destructive) {
                    showResetConfirmation = true
                }
            } footer: {
                Text("Setzt alle Farben auf die Standardwerte zurück.")
            }
        }
        .navigationTitle("Design anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Standardfarben wiederherstellen?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zurücksetzen", role: .destructive) {
                theme.resetToDefaults()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle eigenen Farbeinstellungen werden gelöscht.")
        }
    }
}
```

- [ ] **Schritt 2: Gesamtdatei prüfen**

`ThemeView.swift` enthält jetzt in dieser Reihenfolge:
1. `import SwiftUI`
2. `ThemePreviewCard`
3. `NormalThemeSection`
4. `AdvancedThemeSection`
5. `ThemeView`

Prüfe: Kein Symbol ist doppelt definiert, alle referenzierten Typen existieren.

---

## Task 6: App-Verdrahtung — CaloApp.swift + ProfileView.swift

**Files:**
- Modify: `CaloApp.swift` (AppTheme instanziieren + in Environment legen)
- Modify: `ProfileView.swift` (NavigationLink + eine Farbe)

- [ ] **Schritt 1: CaloApp.swift — AppTheme instanziieren**

In `CaloApp.swift`, füge eine neue Property hinzu und reiche sie per `.environment()` weiter:

```swift
// Vorher:
var body: some Scene {
    WindowGroup {
        ContentView()
            .modelContainer(container)
    }
}

// Nachher:
@State private var appTheme = AppTheme()

var body: some Scene {
    WindowGroup {
        ContentView()
            .modelContainer(container)
            .environment(appTheme)
    }
}
```

- [ ] **Schritt 2: ProfileView.swift — NavigationLink hinzufügen**

In `ProfileView.swift`, füge den NavigationLink in die bestehende Section direkt vor `NavigationLink("Optionale Features")` ein:

```swift
// Vorher (Zeile ~186):
Section {
    NavigationLink("Optionale Features") {
        OptionalFeaturesView()
    }
}

// Nachher:
Section {
    NavigationLink("Design anpassen") {
        ThemeView()
    }
    NavigationLink("Optionale Features") {
        OptionalFeaturesView()
    }
}
```

- [ ] **Schritt 3: ProfileView.swift — Kalorienzahl auf theme.accent**

`ProfileView.swift` verwendet `@Environment(AppTheme.self)`. Füge die Environment-Property am Anfang von `ProfileView` (nach den bestehenden `@Query`-Properties) hinzu:

```swift
@Environment(AppTheme.self) private var theme
```

Dann ersetze in der Kalorienziel-Section (ca. Zeile 66):

```swift
// Vorher:
.foregroundStyle(.green)

// Nachher (nur die eine Zeile in der Kalorienziel-Card):
.foregroundStyle(theme.accent)
```

- [ ] **Schritt 4: Build-Checkpoint 1**

Sync zu iPad → Swift Playgrounds → Build. Erwartetes Ergebnis:
- App startet
- Im Profil-Tab erscheint „Design anpassen" als NavigationLink
- Tippen öffnet den Theme-Maker-Screen
- Segment-Control wechselt zwischen Normal und Fortgeschritten
- Farb-Swatches und ColorPicker sind sichtbar
- Vorschau-Card zeigt sich

---

## Task 7: DiaryView.swift — Farb-Migration

**Files:**
- Modify: `DiaryView.swift`

- [ ] **Schritt 1: `@Environment(AppTheme.self)` in CalorieSummaryCard**

`CalorieSummaryCard` ist eine struct in `DiaryView.swift`. Füge die Environment-Property hinzu:

```swift
// In CalorieSummaryCard, nach den bestehenden Properties:
@Environment(AppTheme.self) private var theme
```

- [ ] **Schritt 2: ringColor und cardTintColor auf theme.accent**

Ersetze die beiden computed Properties (ca. Zeile 353–363):

```swift
// Vorher:
private var ringColor: Color {
    if isOverBudget { return .red }
    if progress >= 0.8 { return .orange }
    return .green
}

private var cardTintColor: Color {
    if isOverBudget { return .red }
    if progress >= 0.8 { return .orange }
    return .green
}

// Nachher:
private var ringColor: Color {
    if isOverBudget { return .red }
    if progress >= 0.8 { return .orange }
    return theme.accent
}

private var cardTintColor: Color {
    if isOverBudget { return .red }
    if progress >= 0.8 { return .orange }
    return theme.accent
}
```

- [ ] **Schritt 3: Kalorien-Übertrag-Farbe (ca. Zeile 418)**

```swift
// Vorher:
color: carryoverKcal > 0 ? .green.opacity(0.85) : .red.opacity(0.85)

// Nachher:
color: carryoverKcal > 0 ? theme.accent.opacity(0.85) : Color.red.opacity(0.85)
```

- [ ] **Schritt 4: Makro-Farben in macroCell-Aufrufen (ca. Zeile 435–439)**

```swift
// Vorher:
macroCell("Protein",     value: protein, target: proteinTarget, color: .blue)
macroCell("Kohlenhydr.", value: carbs,   target: carbsTarget,   color: .orange)
macroCell("Fett",        value: fat,     target: fatTarget,     color: .yellow)

// Nachher:
macroCell("Protein",     value: protein, target: proteinTarget, color: theme.protein)
macroCell("Kohlenhydr.", value: carbs,   target: carbsTarget,   color: theme.carbs)
macroCell("Fett",        value: fat,     target: fatTarget,     color: theme.fat)
```

- [ ] **Schritt 5: Plus-Button (ca. Zeile 691)**

```swift
// Vorher:
.foregroundStyle(.green)

// Nachher (nur den plus.circle.fill Button):
.foregroundStyle(theme.accent)
```

- [ ] **Schritt 6: DiaryEntryEditSheet — Kalorienzahl + Portion-Button (ca. Zeilen 926, 932)**

Füge `@Environment(AppTheme.self) private var theme` in die `DiaryEntryEditSheet`-Struct ein, dann:

```swift
// Vorher (beide Stellen):
.foregroundStyle(.green)

// Nachher:
.foregroundStyle(theme.accent)
```

- [ ] **Schritt 7: WaterCard — alle .blue ersetzen**

Füge `@Environment(AppTheme.self) private var theme` in `WaterCard` ein, dann ersetze:

```swift
// Zeile ~567 (Label):
// Vorher: .foregroundStyle(.blue)
.foregroundStyle(theme.water)

// Zeile ~578 (Balken-Hintergrund):
// Vorher: .fill(Color.blue.opacity(0.12))
.fill(theme.water.opacity(0.12))

// Zeile ~581 (Balken-Füllung):
// Vorher: .fill(Color.blue.opacity(progress >= 1 ? 1.0 : 0.65))
.fill(theme.water.opacity(progress >= 1 ? 1.0 : 0.65))

// Zeile ~608 (Checkmark-Label):
// Vorher: .foregroundStyle(.blue)
.foregroundStyle(theme.water)

// Zeile ~621 (waterButton Hintergrund):
// Vorher: .background(Color.blue.opacity(0.12))
.background(theme.water.opacity(0.12))

// Zeile ~622 (waterButton Text):
// Vorher: .foregroundStyle(.blue)
.foregroundStyle(theme.water)
```

---

## Task 8: FoodSearchSheet.swift + SearchView.swift

**Files:**
- Modify: `FoodSearchSheet.swift`
- Modify: `SearchView.swift`

- [ ] **Schritt 1: FoodSearchSheet — Environment hinzufügen**

Grep nach `.green` und `.blue` in `FoodSearchSheet.swift`. Füge in die Haupt-Struct `FoodSearchSheet` (und in `AmountInputView` und `RecentFoodChip` wenn sie dort `.green` verwenden) jeweils hinzu:

```swift
@Environment(AppTheme.self) private var theme
```

Ersetze alle `.foregroundStyle(.green)`, `.foregroundStyle(Color.green)`, `.background(Color.green...)` mit `theme.accent`-Varianten. Beispiel:

```swift
// Vorher:
.foregroundStyle(.green)
// Nachher:
.foregroundStyle(theme.accent)

// Vorher:
.background(Color.green.opacity(0.15))
// Nachher:
.background(theme.accent.opacity(0.15))
```

- [ ] **Schritt 2: SearchView — Environment hinzufügen**

Gleiche Vorgehensweise wie Schritt 1 für `SearchView.swift`: `@Environment(AppTheme.self) private var theme` hinzufügen, alle `.green` auf `theme.accent` umstellen.

---

## Task 9: StatsView.swift

**Files:**
- Modify: `StatsView.swift`

- [ ] **Schritt 1: Environment in StatsView**

```swift
@Environment(AppTheme.self) private var theme
```

- [ ] **Schritt 2: Chart-Akzentfarben ersetzen**

Grepe nach `.green` in `StatsView.swift`. Die Kalorien-Balken und Gewichts-Chart-Linien verwenden `.green`. Ersetze mit `theme.accent`:

```swift
// Vorher (überall wo der Chart-Inhalt grün ist):
.foregroundStyle(.green)
// oder:
.foregroundStyle(Color.green)

// Nachher:
.foregroundStyle(theme.accent)
```

Achtung: BMI-Balken-Farben (blau/grün/orange/rot in `BMIScaleRow`) bleiben unverändert — sie sind semantisch an BMI-Kategorien gebunden, nicht am Theme.

---

## Task 10: RecipesView + RecipeEditorView + OnboardingView

**Files:**
- Modify: `RecipesView.swift`
- Modify: `RecipeEditorView.swift`
- Modify: `OnboardingView.swift`

- [ ] **Schritt 1: RecipesView**

`@Environment(AppTheme.self) private var theme` hinzufügen. Alle `.green`-Farben für Buttons/Labels auf `theme.accent` umstellen.

- [ ] **Schritt 2: RecipeEditorView**

Gleich wie Schritt 1.

- [ ] **Schritt 3: OnboardingView**

`@Environment(AppTheme.self) private var theme` hinzufügen. Akzent-Buttons und Highlights auf `theme.accent`. Achtung: `NumericStepperView` (auch in dieser Datei) ggf. anpassen.

- [ ] **Schritt 4: Build-Checkpoint 2 — Abschluss**

Sync zu iPad → Build. Vollständiger Test:

1. App startet, Tagebuch zeigt grünen Ring + korrekte Makro-Farben
2. Profil → „Design anpassen" → Normal-Modus → Swatch antippen → Ring ändert Farbe sofort
3. Fortgeschritten-Modus → Protein-Farbe ändern → Tagebuch zeigt neue Protein-Balken-Farbe
4. Reset-Button → Bestätigen → Alle Farben zurück auf Standard
5. App neu starten → gewählte Farben bleiben erhalten (UserDefaults-Persistenz)

---

## Offene Punkte (nicht im Scope)

- BMI-Balken-Farben bleiben fix (semantisch an BMI-Kategorien gebunden)
- Mikronährstoff-Balken bleiben lila/fix (zu selten sichtbar, kein Mehrwert)
- Dark/Light-Toggle für Makros/Wasser/Warnung ist nicht implementiert (nur Akzent hat Dark/Light-Trennung)
