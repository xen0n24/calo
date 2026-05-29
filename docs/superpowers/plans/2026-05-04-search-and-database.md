# Erweiterte Datenbank + Intelligente Suche – Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ~1.200 deutsche Lebensmittel als Seed-Datenbank + token-basierte Suche mit deutscher Endungsnormalisierung und Alias-Unterstützung.

**Architecture:** `Food` bekommt ein `searchKeywords`-Feld. `FoodSearch.swift` kapselt den gesamten Suchalgorithmus. Importer migriert auf v2 (löscht alte Seed-Foods, importiert neue). UI-Layer ruft nur noch `FoodSearch.matches/score` auf. Datenbank wird in Teildateien generiert und final gemergt.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 26. Kein git, kein Testsystem.

> **Swift Playgrounds Limits:** Kein verschachteltes `List` in `List`. Kein `@retroactive` auf eigene `@Model`-Typen.

---

## Dateien

| Datei | Aktion |
|---|---|
| `Models.swift` | Ändern: `var searchKeywords: String = ""` zu `Food` |
| `SeedFoodImporter.swift` | Ändern: Key v2, alte Seed-Foods löschen, searchKeywords befüllen |
| `FoodSearch.swift` | Neu: Token + Normalisierungs-Algorithmus |
| `FoodSearchSheet.swift` | Ändern: `localResults` nutzt FoodSearch |
| `SearchView.swift` | Ändern: `localFoods` nutzt FoodSearch |
| `seed-foods-de-part1.json` | Neu (temp): Obst + Gemüse |
| `seed-foods-de-part2.json` | Neu (temp): Fleisch + Geflügel + Fisch |
| `seed-foods-de-part3.json` | Neu (temp): Milch + Käse + Eier + Getreide + Brot |
| `seed-foods-de-part4.json` | Neu (temp): Nüsse + Öle + Fertigprodukte + Wurst |
| `seed-foods-de-part5.json` | Neu (temp): Getränke + Gewürze + Süßes + Sonstiges |
| `seed-foods-de.json` | Ersetzen: Merge aller Parts, ~1.200 Einträge |

---

## Task 1: Food-Modell erweitern

**Files:**
- Modify: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\Models.swift`

- [ ] **Schritt 1: `searchKeywords` zu Food hinzufügen**

In `Models.swift`, in der `Food`-Klasse, nach `var isFavorite: Bool = false` einfügen:

```swift
var searchKeywords: String = ""
```

- [ ] **Schritt 2: Verifizieren**

Datei lesen und sicherstellen dass `Food` jetzt diese Felder hat (in dieser Reihenfolge):
```
var isFavorite: Bool = false
var searchKeywords: String = ""
var createdAt: Date
```

---

## Task 2: SeedFoodImporter auf v2 migrieren

**Files:**
- Modify: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\SeedFoodImporter.swift`

- [ ] **Schritt 1: Key auf v2 ändern und Migration implementieren**

Den Key `"seedFoodsImported_v1"` auf `"seedFoodsImported_v2"` umbenennen:

```swift
private static let importedKey = "seedFoodsImported_v2"
```

- [ ] **Schritt 2: Alte Seed-Foods löschen vor dem Import**

In `importIfNeeded`, vor der Import-Schleife, folgenden Block einfügen (nach dem `alreadyImported`-Check):

```swift
// Alte Seed-Foods löschen (v1-Migration: verhindert Duplikate)
let descriptor = FetchDescriptor<Food>()
if let allFoods = try? context.fetch(descriptor) {
    for food in allFoods where food.source == .seed {
        context.delete(food)
    }
    try? context.save()
}
```

- [ ] **Schritt 3: searchKeywords beim Import befüllen**

Im Import-Loop, beim Erstellen des `Food`-Objekts, die Zeile nach `context.insert(food)` ergänzen:

```swift
// searchKeywords aus aliases + category aufbauen
var keywords: [String] = []
if let aliases = entry.aliases { keywords.append(contentsOf: aliases) }
if let category = entry.category { keywords.append(category) }
food.searchKeywords = keywords.joined(separator: " ").lowercased()
```

- [ ] **Schritt 4: Verifizieren**

Die `importIfNeeded`-Funktion lesen und sicherstellen:
- Key ist `"seedFoodsImported_v2"`
- Vor dem Import werden alte `.seed`-Foods gelöscht
- Nach dem Erstellen jedes Foods wird `searchKeywords` gesetzt

---

## Task 3: FoodSearch.swift erstellen

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\FoodSearch.swift`

- [ ] **Schritt 1: Datei anlegen**

```swift
import Foundation

// MARK: - FoodSearch

/// Kapselt den gesamten lokalen Suchalgorithmus:
/// - Token-basiert: "gegrillte Brust" → Tokens ["gegrillte", "brust"]
/// - Deutsche Endungsnormalisierung: "gegrillte" → "gegrillt"
/// - Alias-Suche: food.searchKeywords wird durchsucht
enum FoodSearch {

    // MARK: - Public API

    /// Gibt true zurück wenn food zur query passt.
    static func matches(food: Food, query: String) -> Bool {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return false }
        let haystack = "\(food.name) \(food.searchKeywords)".lowercased()
        return tokens.allSatisfy { token in
            haystack.contains(token) || haystack.contains(normalize(token))
        }
    }

    /// Höherer Score = relevanter. Für Sortierung der Suchergebnisse.
    /// Exakter Namens-Match > Prefix > Substring > nur Alias.
    static func score(food: Food, query: String) -> Int {
        let q      = query.lowercased().trimmingCharacters(in: .whitespaces)
        let name   = food.name.lowercased()
        let tokens = tokenize(query)

        if name == q                                                        { return 200 }
        if name.hasPrefix(q)                                                { return 100 }
        if name.contains(q)                                                 { return 50  }
        if tokens.allSatisfy({ t in
            name.contains(t) || name.contains(normalize(t))
        })                                                                   { return 20  }
        return 0
    }

    // MARK: - Private

    /// Query in bereinigte Tokens aufteilen (≥ 2 Zeichen, lowercase).
    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
    }

    /// Deutsche Wortendung abschneiden — längste Endung zuerst prüfen.
    /// Mindest-Restlänge verhindert dass kurze Wörter zerstört werden.
    static func normalize(_ word: String) -> String {
        let suffixes: [(String, Int)] = [
            ("ischen", 4), ("ischer", 4), ("isches", 4), ("ischem", 4), ("ische", 4),
            ("lichen", 4), ("licher", 4), ("liches", 4), ("lichem", 4), ("liche", 4),
            ("ten", 3), ("ter", 3), ("tes", 3), ("tem", 3), ("te", 3),
            ("en", 3), ("er", 3), ("es", 3), ("em", 3), ("e", 3)
        ]
        for (suffix, minRest) in suffixes {
            if word.hasSuffix(suffix) && (word.count - suffix.count) >= minRest {
                return String(word.dropLast(suffix.count))
            }
        }
        return word
    }
}
```

- [ ] **Schritt 2: Verifizieren**

Datei lesen und prüfen:
- `matches(food:query:)` verwendet `tokenize` + `normalize`
- `score(food:query:)` gibt 200/100/50/20/0 zurück
- `normalize("gegrillte")` → `"gegrillt"` (drop -e, Restlänge 8 ≥ 3 ✅)
- `normalize("gebratener")` → `"gebraten"` (drop -er, Restlänge 8 ≥ 3 ✅)
- `normalize("Ei")` → `"Ei"` (zu kurz, bleibt unverändert ✅)

---

## Task 4: Suche in FoodSearchSheet + SearchView aktualisieren

**Files:**
- Modify: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\FoodSearchSheet.swift`
- Modify: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\SearchView.swift`

- [ ] **Schritt 1: FoodSearchSheet — localResults ersetzen**

In `FoodSearchSheet.swift`, `localResults` computed property. Aktuell:

```swift
private var localResults: [Food] {
    let q = searchText.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    return allFoods
        .filter { $0.source != .recipe && $0.name.localizedCaseInsensitiveContains(q) }
        .sorted { $0.name < $1.name }
        .prefix(20).map { $0 }
}
```

Ersetzen durch:

```swift
private var localResults: [Food] {
    let q = searchText.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    return allFoods
        .filter { $0.source != .recipe && FoodSearch.matches(food: $0, query: q) }
        .sorted { FoodSearch.score(food: $0, query: q) > FoodSearch.score(food: $1, query: q) }
        .prefix(20).map { $0 }
}
```

- [ ] **Schritt 2: SearchView — localFoods ersetzen**

In `SearchView.swift`, `localFoods` computed property. Aktuell:

```swift
private var localFoods: [Food] {
    let q = searchText.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    return allFoods
        .filter { $0.source != .recipe && $0.name.localizedCaseInsensitiveContains(q) }
        .sorted { $0.name < $1.name }
        .prefix(20).map { $0 }
}
```

Ersetzen durch:

```swift
private var localFoods: [Food] {
    let q = searchText.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    return allFoods
        .filter { $0.source != .recipe && FoodSearch.matches(food: $0, query: q) }
        .sorted { FoodSearch.score(food: $0, query: q) > FoodSearch.score(food: $1, query: q) }
        .prefix(20).map { $0 }
}
```

- [ ] **Schritt 3: iPad-Transfer-Checkpoint**

Dateien übertragen: `Models.swift`, `SeedFoodImporter.swift`, `FoodSearch.swift`, `FoodSearchSheet.swift`, `SearchView.swift`. In Swift Playgrounds öffnen und sicherstellen dass es kompiliert. Noch keine neue Datenbank — die Suche funktioniert bereits verbessert mit den bestehenden ~255 Einträgen.

---

## Task 5: Datenbank Part 1 — Obst + Gemüse + Salate

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de-part1.json`

- [ ] **Schritt 1: Part 1 JSON generieren**

Erstelle `seed-foods-de-part1.json` als JSON-Array mit **~160 Einträgen** aus den Kategorien:
- **Obst** (~60): Äpfel, Birnen, Bananen, Erdbeeren, Heidelbeeren, Himbeeren, Kirschen, Pflaumen, Pfirsiche, Aprikosen, Mango, Ananas, Kiwi, Orange, Zitrone, Grapefruit, Mandarine, Weintrauben, Melone, Wassermelone, Avocado, Feigen, Datteln, Rosinen, Cranberries, Kokosnuss, Granatapfel, Papaya, Lychee, Maracuja, Johannisbeeren, Stachelbeeren, Brombeeren, Mirabellen, Zwetschgen, Quitte, Clementine, Pomelo, Limette, Physalis
- **Gemüse** (~70): Karotte, Brokkoli, Blumenkohl, Spinat, Tomate, Gurke, Paprika, Zucchini, Aubergine, Zwiebel, Knoblauch, Lauch, Sellerie, Kartoffel, Süßkartoffel, Kürbis, Kohlrabi, Rotkohl, Weißkohl, Wirsing, Rosenkohl, Spargel, Bohnen, Erbsen, Linsen, Kichererbsen, Mais, Rote Bete, Radieschen, Rettich, Fenchel, Artischocke, Pak Choi, Mangold, Grünkohl, Radicchio, Rucola, Endiviensalat, Eisbergsalat, Kopfsalat, Feldsalat, Chicoree, Porree, Frühlingszwiebeln, Ingwer, Chili, Jalapeño, Petersilienwurzel, Pastinake, Topinambur, Kresse, Bambus
- **Salate** (~30): Als eigene Kategorie mit Fertig-Salaten (Tomatensalat, griechischer Salat, etc.) — NICHT als separate Kategorie in den `category`-Feld, sondern als Gemüse oder Fertigprodukt

**JSON-Format** (jeder Eintrag exakt so):

```json
{
  "name": "Apfel",
  "aliases": ["äpfel", "apple", "obst"],
  "category": "Obst",
  "default_serving_grams": 150,
  "kcal": 52,
  "protein": 0.3,
  "carbs": 14.0,
  "sugar": 10.4,
  "fat": 0.2,
  "saturated_fat": 0.0,
  "fiber": 2.4,
  "salt": 0.0
}
```

**Pflichtfelder:** `name`, `kcal`, `protein`, `carbs`, `fat`  
**Optionale Felder:** `aliases`, `category`, `default_serving_grams`, `sugar`, `saturated_fat`, `fiber`, `salt`

**Qualitätsanforderungen:**
- Nährwerte pro 100g, realistisch (basierend auf Bundeslebensmittelschlüssel / USDA-Werten)
- `aliases` enthält: Pluralform, regionale Namen, englische Bezeichnung, häufige Schreibweisen, Zubereitungsformen (roh, gekocht, gegart)
- `category` auf Deutsch, konsistent: "Obst", "Gemüse", "Hülsenfrüchte"
- `default_serving_grams`: typische Portion in Gramm (Apfel ~150g, Karotte ~80g, etc.)
- Namen sind die **gebräuchlichste deutsche Hauptbezeichnung**

---

## Task 6: Datenbank Part 2 — Fleisch, Geflügel, Fisch, Meeresfrüchte

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de-part2.json`

- [ ] **Schritt 1: Part 2 JSON generieren**

Erstelle `seed-foods-de-part2.json` als JSON-Array mit **~200 Einträgen**:

**Fleisch (~70):**
- Rind: Rinderhack, Rinderfilet, Rindersteak, Rinderbraten, Rinderschmorbraten, Tafelspitz, Entrecôte, Kalbfleisch, Kalbsschnitzel, Kalbsleber
- Schwein: Schweinefilet, Schweinekotelett, Schweinebauch, Schweineschulter, Schweinehack, Schweinerücken, Eisbein, Spanferkel
- Lamm: Lammfilet, Lammkotelett, Lammhack, Lammkeule, Lammschulter
- Wild: Rehfilet, Hirschgulasch, Wildschweinhack, Wildschweinkeule
- Zubereitung: jeweils roh und gebraten/gegrillt/gekocht als separate Einträge mit korrekten Nährwerten (gegart = weniger Wasser, mehr Protein/Fett pro 100g)

**Geflügel (~60):**
- Hähnchen: Hähnchenbrust roh, Hähnchenbrust gegrillt, Hähnchenbrust gebraten, Hähnchenschenkel, Hähnchenflügel, Hähnchen ganz, Hähnchenkeule
- Pute: Putenbrust roh, Putenbrust gegrillt, Putenhack, Putenkeule
- Ente, Gans, Truthahn
- Wachtel, Tauben

**Fisch (~50):**
- Lachs (roh, geräuchert, gegart), Thunfisch (frisch, Dose in Wasser, Dose in Öl), Dorsch/Kabeljau, Forelle, Hering, Makrele, Sardinen, Scholle, Seelachs, Tilapia, Wolfsbarsch, Zander, Pangasius

**Meeresfrüchte (~20):**
- Garnelen (roh, gegart), Krabben, Muscheln, Tintenfisch, Hummer, Jakobsmuscheln, Calamari

**aliases-Beispiele:**
- Hähnchenbrust gegrillt: `["hühnchen", "chicken", "geflügel", "gegrillte hähnchenbrust", "gegrilltes hähnchen", "grill"]`
- Thunfisch Dose: `["thun", "tuna", "fischdose", "dosenthunfisch"]`

Gleiche Format- und Qualitätsanforderungen wie Task 5.

---

## Task 7: Datenbank Part 3 — Milch, Käse, Eier, Getreide, Brot

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de-part3.json`

- [ ] **Schritt 1: Part 3 JSON generieren**

Erstelle `seed-foods-de-part3.json` als JSON-Array mit **~210 Einträgen**:

**Milchprodukte (~60):**
- Milch: Vollmilch, Halbfettmilch, Magermilch, Laktosefreie Milch, Hafermilch, Mandelmilch, Sojamilch, Kokosmilch, Reismilch
- Joghurt: Joghurt 3,5%, Joghurt 1,5%, Joghurt 0,1%, Griechischer Joghurt, Skyr, Fruchtjoghurt
- Sahne: Schlagsahne, Saure Sahne, Crème fraîche, Schmand, Kefir, Buttermilch
- Quark: Magerquark, Speisequark 20%, Quark 40%, Frischkäse, Mascarpone, Ricotta
- Butter, Margarine, Ghee

**Käse (~40):**
- Gouda, Edamer, Emmentaler, Bergkäse, Cheddar, Mozzarella, Parmesan, Pecorino, Brie, Camembert, Gorgonzola, Roquefort, Feta, Hüttenkäse, Schmelzkäse, Kochkäse, Büffelmozzarella, Halloumi, Manchego, Gruyère

**Eier (~10):**
- Hühnerei ganz, Eigelb, Eiweiß, Hühnerei hartgekocht, Hühnerei Rührei, Hühnerei Spiegelei, Wachtelei

**Getreide & Hülsenfrüchte (~50):**
- Haferflocken, Müsli, Cornflakes, Weizenmehl, Dinkelmehl, Roggenmehl, Grieß, Polenta, Couscous, Bulgur, Quinoa, Amaranth, Hirse, Gerste, Buchweizen
- Reis: weißer Reis gekocht, Vollkornreis, Jasminreis, Basmati, Parboiled, Risottoreis
- Hülsenfrüchte: Rote Linsen, Grüne Linsen, Belugalinsen, Kidneybohnen, Schwarze Bohnen, Weiße Bohnen, Edamame, Tofu, Tempeh, Seitan

**Brot & Pasta (~50):**
- Brot: Weißbrot, Toastbrot, Vollkornbrot, Roggenbrot, Graubrot, Laugenbrezel, Baguette, Ciabatta, Knäckebrot
- Pasta: Spaghetti (trocken/gekocht), Penne, Fusilli, Tagliatelle, Linguine, Vollkornnudeln, Eiernudeln, Gnocchi
- Sonstiges: Tortilla, Pita, Naan, Wrap

Gleiche Format- und Qualitätsanforderungen wie Task 5.

---

## Task 8: Datenbank Part 4 — Nüsse, Öle, Fertigprodukte, Wurst

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de-part4.json`

- [ ] **Schritt 1: Part 4 JSON generieren**

Erstelle `seed-foods-de-part4.json` als JSON-Array mit **~220 Einträgen**:

**Nüsse & Samen (~40):**
- Mandeln, Walnüsse, Cashews, Erdnüsse, Haselnüsse, Pistazien, Macadamia, Pekannüsse, Paranüsse, Pinienkerne
- Samen: Chiasamen, Leinsamen, Sonnenblumenkerne, Kürbiskerne, Sesam, Hanfsamen, Mohn
- Aufstriche: Erdnussbutter, Mandelmus, Cashewmus, Tahini

**Öle & Fette (~20):**
- Olivenöl, Rapsöl, Sonnenblumenöl, Kokosöl, Leinöl, Walnussöl, Sesamöl, Avocadoöl, Butter (hier auch), Schmalz, Kokosfett

**Wurst & Aufschnitt (~60):**
- Salami, Cervelat, Chorizo, Mortadella, Bierschinken, Lyoner, Fleischwurst, Jagdwurst
- Schinken: Kochschinken, Roher Schinken, Serrano, Prosciutto, Schwarzwälder Schinken
- Aufschnitt: Putenbrust aufgeschnitten, Hähnchenbrust aufgeschnitten, Leberwurst, Teewurst, Mettwurst, Bratwurst, Bockwurst, Wiener Würstchen, Weißwurst, Blutwurst

**Fertigprodukte (~70):**
- TK-Pizza (Margherita, Salami, etc.), Tiefkühlgemüse, TK-Pommes, TK-Schnitzel
- Dose: Tomaten gehackt, Tomatenmark, Kichererbsen Dose, Kidneybohnen Dose, Thunfisch Dose (hier nochmal als Fertigprodukt)
- Convenience: Hummus, Guacamole, Tzatziki, Aioli
- Snacks: Chips (Paprika, Salz), Popcorn, Cracker, Reiswaffeln, Brezel

**Fastfood (~30):**
- Burger (Big Mac-Style, Cheeseburger, Chicken Burger), Pommes Frites, Hot Dog, Döner, Pizza Slice, Currywurst, Chicken Nuggets, Wrap

Gleiche Format- und Qualitätsanforderungen wie Task 5.

---

## Task 9: Datenbank Part 5 — Getränke, Gewürze, Süßes, Sonstiges

**Files:**
- Create: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de-part5.json`

- [ ] **Schritt 1: Part 5 JSON generieren**

Erstelle `seed-foods-de-part5.json` als JSON-Array mit **~210 Einträgen**:

**Getränke (~80):**
- Säfte: Orangensaft, Apfelsaft, Traubensaft, Multivitaminsaft, Tomatensaft, Karottensaft (alle mit und ohne Zucker)
- Softdrinks: Cola, Cola Zero/Light, Fanta, Sprite, Limonade, Energy Drink, Eistee
- Milchgetränke: Kakao, Milchkaffee, Latte Macchiato, Cappuccino, Chai Latte
- Kaffee: Espresso, Filterkaffee, Americano (ohne Zusätze = 0 kcal, mit Milch = Werte angeben)
- Tee: Schwarztee, Grüntee, Kräutertee (ohne Zucker ~0 kcal)
- Alkohol: Bier (hell, dunkel, Weizen, alkoholfrei), Wein (rot, weiß, Rosé), Sekt, Schnaps, Vodka, Whisky
- Wasser: Wasser still (0 kcal), Wasser mit Kohlensäure (0 kcal)
- Sportgetränke: Isotonisches Getränk, Proteinshake (Vanille, Schokolade)

**Gewürze & Saucen (~80):**
- Gewürze (meist ~0-20 kcal/100g aber hohe Dichte): Salz, Pfeffer, Paprikapulver, Kurkuma, Zimt, Kreuzkümmel, Oregano, Basilikum, Thymian, Rosmarin, Curry, Chilipulver, Knoblauchpulver, Zwiebelpulver, Muskat
- Saucen: Ketchup, Mayonnaise, Senf (mild, scharf), BBQ-Sauce, Sojasauce, Worcestershiresauce, Tabasco, Sriracha, Teriyaki-Sauce, Hoisin-Sauce, Pesto (rot, grün), Tomatensoße, Béchamel
- Dressings: Vinaigrette, Joghurt-Dressing, Caesar Dressing, Balsamico
- Essig, Zitronensaft

**Süßes & Backwaren (~80):**
- Schokolade: Vollmilch, Zartbitter, Weiß, Nuss-Nougat-Creme (Nutella-Style)
- Riegel: Müsliriegel, Proteinriegel, Schokoriegel (Snickers-Style, Mars-Style, Kit Kat-Style)
- Kuchen: Käsekuchen, Schwarzwälder Kirschtorte, Apfelkuchen, Marmorkuchen, Muffin, Croissant, Donut
- Kekse: Butterkeks, Haferkeks, Oreo-Style, Spekulatius, Lebkuchen
- Eis: Vanilleeis, Schokoladeneis, Erdbeereis, Fruchtsorbet
- Bonbons, Gummibärchen, Fruchtgummi, Weingummi, Lakritz
- Zucker: Weißzucker, Brauner Zucker, Honig, Ahornsirup, Agavensirup, Stevia

**Sonstiges (~50):**
- Babynahrung: Breie, Gläschen
- Sporternährung: Whey Protein, Casein, BCAA (als Pulver)
- Nahrungsergänzung: Vitamin-Tabs (0 kcal)
- Suppen: Hühnerbrühe, Tomatensuppe, Minestrone, Linseneintopf
- Saucen/Gerichte: Bolognese, Gulasch, Chili con Carne (fertig)

Gleiche Format- und Qualitätsanforderungen wie Task 5.

---

## Task 10: Parts mergen + seed-foods-de.json finalisieren

**Files:**
- Modify: `C:\Users\jonat\iCloudDrive\iCloud~com~apple~Playgrounds\Calo\seed-foods-de.json`
- Delete: `seed-foods-de-part1.json` bis `seed-foods-de-part5.json`

- [ ] **Schritt 1: Alle Parts einlesen und mergen**

Alle 5 Part-Dateien einlesen:
- `seed-foods-de-part1.json`
- `seed-foods-de-part2.json`
- `seed-foods-de-part3.json`
- `seed-foods-de-part4.json`
- `seed-foods-de-part5.json`

In ein einziges JSON-Array zusammenführen und als `seed-foods-de.json` speichern. Reihenfolge: Part1 zuerst, dann Part2-5.

- [ ] **Schritt 2: Duplikate prüfen**

Sicherstellen dass kein `name`-Wert doppelt vorkommt. Falls Duplikate gefunden werden: den Eintrag mit mehr Feldern behalten, den anderen entfernen.

- [ ] **Schritt 3: JSON validieren**

Sicherstellen dass:
- Das JSON gültig ist (valid JSON array)
- Jeder Eintrag mindestens `name`, `kcal`, `protein`, `carbs`, `fat` hat
- Alle Zahlenwerte als Zahlen vorliegen (nicht als Strings)
- Mindestens 1.000 Einträge im finalen Array

- [ ] **Schritt 4: Part-Dateien löschen**

`seed-foods-de-part1.json` bis `seed-foods-de-part5.json` löschen (Aufräumen).

- [ ] **Schritt 5: iPad-Transfer-Checkpoint (finaler Build)**

Datei übertragen: `seed-foods-de.json`. App auf iPad starten (Swift Playgrounds). Da der Import-Key auf v2 geändert wurde, importiert die App automatisch die neue Datenbank. Testen:
- Suche "gegrillt" → findet "Hähnchenbrust gegrillt" ✅
- Suche "gegrillte" → findet "Hähnchenbrust gegrillt" (Normalisierung -e → gegrillt) ✅
- Suche "chicken" → findet "Hähnchenbrust gegrillt" (via alias) ✅
- Suche "hühnchen brust" → findet "Hähnchenbrust gegrillt" (Token-Suche) ✅
- Suche "apfel" → findet Apfel-Einträge ganz oben ✅
