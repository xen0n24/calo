# Design: Erweiterte Lebensmitteldatenbank + Intelligente Suche

**Datum:** 2026-05-04  
**Projekt:** Calo – iOS Kalorientracking-App  
**Status:** Genehmigt

---

## 1. Ziel

- ~1.200 deutsche Lebensmittel als Seed-Datenbank (statt bisher ~255)
- Suche findet Einträge auch bei flektierten Formen ("gegrillte" → "gegrillt"), anderen Wortreihenfolgen ("Brust Hähnchen" → "Hähnchenbrust") und Synonymen ("Hühnchen" → "Hähnchen")

---

## 2. Datenmodell

### Food-Erweiterung

`Food` (in `Models.swift`) bekommt ein neues Feld:

```swift
var searchKeywords: String = ""
```

Inhalt: Leerzeichen-getrennter String mit Aliasen, Synonymen, Kategorie und englischer Bezeichnung.  
Beispiel für "Hähnchenbrust gegrillt": `"hühnchen chicken geflügel poultry brust grill gegrillt"`

### Importer-Key & Migration

Neuer Key `"seedFoodsImported_v2"` in `SeedFoodImporter.swift`. Ablauf beim App-Start:

1. Ist `v2`-Key gesetzt → überspringen
2. Ist `v2`-Key **nicht** gesetzt → **alle bestehenden Foods mit `source == .seed` löschen** (verhindert Duplikate mit v1-Daten), dann neue ~1.200 Einträge importieren, `v2`-Key setzen

Custom-Foods (`source == .custom`), OFI-Foods (`source == .openFoodFacts`) und Recipe-Foods (`source == .recipe`) bleiben erhalten.

### JSON-Struktur (unverändert)

```json
{
  "name": "Hähnchenbrust gegrillt",
  "aliases": ["hühnchen", "chicken", "geflügel", "gegrillte hähnchenbrust"],
  "category": "Geflügel",
  "default_serving_grams": 150,
  "kcal": 165,
  "protein": 31.0,
  "carbs": 0.0,
  "fat": 3.6,
  ...
}
```

---

## 3. Suchalgorithmus

### Neue Datei: `FoodSearch.swift`

Enthält eine einzige öffentliche Funktion:

```swift
enum FoodSearch {
    static func matches(food: Food, query: String) -> Bool
    static func score(food: Food, query: String) -> Int  // für Sortierung
}
```

### Algorithmus (matches)

1. **Tokenisierung:** Query in Wörter splitten, Leerzeichen und Sonderzeichen als Trenner
2. **Normalisierung je Token:** Deutsche Endungen abschneiden (Tabelle unten)
3. **Suchraum aufbauen:** `"\(food.name) \(food.searchKeywords)"` lowercased
4. **Match:** Lebensmittel trifft zu wenn **alle** Tokens entweder direkt oder normalisiert im Suchraum vorkommen

### Normalisierungs-Tabelle (längste Endung zuerst prüfen)

| Endung (abschneiden) | Mindest-Restlänge |
|---|---|
| -ischen, -ischer, -isches, -ischem, -ische | 4 |
| -lichen, -licher, -liches, -lichem, -liche | 4 |
| -ten, -ter, -tes, -tem, -te | 3 |
| -en, -er, -es, -em, -e | 3 |

Beispiele:
- "gegrillte" → "gegrillt" (drop -e, Restlänge 8 ≥ 3 ✅)
- "gebratener" → "gebraten" (drop -er, Restlänge 8 ≥ 3 ✅)
- "rohe" → "roh" (drop -e, Restlänge 3 ≥ 3 ✅)
- "Ei" → "Ei" (zu kurz für Normalisierung, bleibt unverändert)

### Sortierung (score)

Höherer Score = weiter oben:
- Name beginnt mit Query-String: +100
- Name enthält Query-String direkt: +50
- Alle Tokens im Namen (nicht nur Keywords): +20
- Alias-Treffer: +0 (erscheint nach direkten Namenstreffern)

### Anwendung

`FoodSearchSheet.swift` und `SearchView.swift`: Das bestehende `.filter { $0.name.localizedCaseInsensitiveContains(q) }` wird ersetzt durch `.filter { FoodSearch.matches(food: $0, query: q) }` + Sortierung nach Score.

---

## 4. Datenbankinhalt (~1.200 Einträge)

| Kategorie | Einträge |
|---|---|
| Obst | ~60 |
| Gemüse & Salate | ~100 |
| Fleisch & Geflügel | ~120 |
| Fisch & Meeresfrüchte | ~80 |
| Milch, Käse & Eier | ~110 |
| Getreide, Brot & Pasta | ~100 |
| Nüsse & Samen | ~40 |
| Öle & Fette | ~30 |
| Fertigprodukte & Wurst | ~150 |
| Getränke | ~80 |
| Gewürze & Saucen | ~80 |
| Süßes & Backwaren | ~120 |
| Sonstiges (Hülsenfrüchte, Babynahrung) | ~50 |
| **Gesamt** | **~1.200** |

Jeder Eintrag enthält:
- `name`: Deutsche Hauptbezeichnung
- `aliases`: Synonyme, Regionalbezeichnungen, Englisch, häufige Schreibweisen
- `category`: Kategorie (für spätere Filterung)
- Nährwerte: kcal, protein, carbs, fat (Pflicht), sugar, fiber, salt, saturated_fat (optional)
- `default_serving_grams`: Typische Portion

---

## 5. Dateien (neu/geändert)

| Datei | Änderung |
|---|---|
| `seed-foods-de.json` | Ersetzen: ~255 → ~1.200 Einträge |
| `Models.swift` | Ändern: `var searchKeywords: String = ""` zu Food |
| `SeedFoodImporter.swift` | Ändern: Key v2, searchKeywords aus aliases + category befüllen |
| `FoodSearch.swift` | Neu: Token + Normalisierungs-Algorithmus |
| `FoodSearchSheet.swift` | Ändern: FoodSearch.matches verwenden + nach Score sortieren |
| `SearchView.swift` | Ändern: FoodSearch.matches verwenden + nach Score sortieren |
