# Calo – Projektstand

## Vollständig implementierte Features

### Core
- [x] Onboarding (8 Schritte: Geschlecht, Alter, Größe, Gewicht, Aktivität, Ziel, Rate, Wasserziel)
- [x] Tagebuch mit Datumsnavigation (Vergangenheit + Zukunft)
- [x] Kalorien-Ring mit Fortschrittsanzeige
- [x] Makro-Fortschrittsbalken (Protein, Kohlenhydrate, Fett)
- [x] Einträge kopieren (von gestern / von vor einer Woche)
- [x] Diary-Einträge nachträglich bearbeiten (Gramm, Mahlzeit, Datum, Notiz)
- [x] Notizen zu Tagebucheinträgen (Notiz-Icon in EntryRow wenn vorhanden)

### Lebensmittel & Suche
- [x] Lokale Lebensmitteldatenbank (~1200 Einträge, seed-foods-de.json)
- [x] Open Food Facts Integration (Online-Suche + Barcode-Lookup)
- [x] Barcode-Scanner (VisionKit)
- [x] Eigene Lebensmittel erstellen und bearbeiten
- [x] Lebensmittel löschen (nur custom)
- [x] Favoriten-Markierung (Swipe-Aktion, Favoriten-Tab)
- [x] Vorschläge: zuletzt genutzt + häufig genutzt
- [x] Portionsgrößen pro Lebensmittel (name + grams, JSON-gespeichert)
- [x] Einheiten pro Lebensmittel (g / ml)
- [x] Freie Nährwert-Eingabe (manuell, ohne Food-Objekt)

### Rezepte
- [x] Rezepte mit gramm-basierter Skalierung
- [x] Rezept-Editor mit Zutatenpicker
- [x] Rezept direkt ins Tagebuch loggen (Snapshot-Food)
- [x] Favoriten für Rezepte

### Wassertracking
- [x] Tägliches Wasserziel
- [x] Schnellbuttons (+150 / +250 / +500 ml)
- [x] Rückgängig-Button

### Statistiken
- [x] Gewichtsverlauf (90 Tage, SwiftUI Charts)
- [x] Kalorienbalken (14 Tage)
- [x] Logging-Streak
- [x] TDEE-Anzeige
- [x] Adaptiver Kalorienziel-Algorithmus (MacroFactor-Stil, 14-Tage-Fenster)
- [x] Gewichtsziel-Prognose (ab ≥ 14 Tage Daten, Zielgewicht erforderlich)

### Profil
- [x] Profil bearbeiten (Ziel, Aktivität, Rate, Kalorienziel, Makros, Wasserziel)
- [x] BMI-Anzeige mit Kategorie und Farbkodierung
- [x] TDEE-Berechnung (Mifflin-St-Jeor)
- [x] Zielgewicht setzen (für Prognose)
- [x] Lokale Benachrichtigungen (tägliches Logging, wöchentliches Wiegen)

### Mikronährstoffe (optionales Feature)
- [x] Anzeige: Ballaststoffe, Zucker, Salz, gesättigte Fette im Tagebuch
- [x] Tagesziele setzen (im Profil bearbeiten)
- [x] Fortschrittsbalken im Tagebuch

### Mahlzeit-Templates
- [x] Vorlagen erstellen (aus Tagebuch-Mahlzeit oder manuell)
- [x] Vorlagen einfügen ins Tagebuch
- [x] Vorlagen verwalten (Profil-Tab)

### Optionale Features
- [x] Körpermaße tracken (Taillenumfang etc., eigene Typen + Verlauf)
- [x] Foto-Erkennung per KI (Apple Intelligence / FoundationModels, iOS 26)
- [x] Feature-Flags unter Profil → Optionale Features

### Datensicherung
- [x] Backup exportieren (JSON, Share-Sheet)
- [x] Backup importieren (nur fehlende Einträge werden hinzugefügt)

---

## Bugfixes
- [x] Scroll-Bug: Karten unter langen Mahlzeiten verschwanden (LazyVStack → VStack)
- [x] Makro-Preview beim Einloggen: live kcal + Makros passen sich bei Gramm-Änderung an

## UI-Polishing (abgeschlossen)

- [x] EntryRow Makro-Streifen
- [x] Haptic Feedback
- [x] CalorieSummaryCard Gradient
- [~] MealSectionCard Farbstreifen — rückgängig gemacht, zu viele Farben
- [x] Leer-Zustände (ContentUnavailableView)
- [x] Eintrags-Animation
- [x] Ring-Erscheinungs-Animation (mit hasAppeared-Fix für Tab-Wechsel)
- [x] FoodSearchSheet Chips (horizontale Scroll-Chips für zuletzt genutzte Foods)
- [x] StatsView Layout (ScrollView + Karten, kein List mehr)
- [x] BMI Visualisierung (visueller Farbbalken mit Pfeilmarkierung in ProfileView)
- [x] Tab Bar Indikator (Badge auf Tagebuch-Tab wenn heute nichts geloggt)
- [x] Typografie Konsistenz (.monospacedDigit, .fontDesign(.rounded))

---

## Körpermaße (vollständig in StatsView)

- [x] Maßtypen anlegen (Name + Einheit) — komplett aus Profil entfernt, nur noch in Statistik
- [x] Messungen eintragen (BodyMeasurementLoggerSheet mit korrektem Typ-Vorauswahl via sheet(item:))
- [x] Separat-Ansicht: eine Chart-Karte pro Maßtyp (LineMark + PointMark, 90 Tage)
- [x] Kombiniert-Ansicht: Gruppen erstellen (GroupManagerSheet), eine Karte pro Gruppe + "Alle Maße"-Karte
- [x] Gruppen verwalten: Maße per Dropdown zuordnen, Gruppen per Swipe löschen
- [x] Prominente "Jetzt messen"/"Neue Messung"-Buttons (volle Breite, dunkles Lila)
- [x] Farben: gedämpfte HSB-Werte (keine System-Farben)

## Bugfixes (diese Session)

- [x] StatsView Kompilierfehler: `let` inside @ChartContentBuilder → MeasurementPoint-Struct + Pre-Compute
- [x] HierarchicalShapeStyle vs Color Ternary-Fehler → explizit Color.orange / Color.green
- [x] BodyMeasurementLoggerSheet: falscher Typ vorausgewählt → sheet(item:) + _selectedType = State(initialValue:)

---

## Offen / Geplant

- [ ] HealthKit (Gewicht import / Kalorien export) — benötigt Capability im Playgrounds-UI
- [ ] App-Icon & visuelles Polishing
