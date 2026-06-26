import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

// MARK: - FoodSelection

/// Kapselt ein lokales Food-Objekt, ein Online-Ergebnis oder ein Rezept.
private enum FoodSelection {
    case local(Food)
    case remote(OFFProduct)
    case recipe(Recipe)

    var name: String {
        switch self {
        case .local(let f):   f.name
        case .remote(let p):  p.displayName
        case .recipe(let r):  r.name
        }
    }

    var kcalPer100g: Double {
        switch self {
        case .local(let f):   f.nutritionPer100g?.kcal ?? 0
        case .remote(let p):  p.nutriments.energyKcal100g ?? 0
        case .recipe(let r):  r.kcalPer100g
        }
    }

    var proteinPer100g: Double {
        switch self {
        case .local(let f):
            return f.nutritionPer100g?.protein ?? 0
        case .remote(let p):
            return p.nutriments.proteins100g ?? 0
        case .recipe(let r):
            guard r.totalCookedWeightGrams > 0 else { return 0 }
            return r.totalNutrition.protein / r.totalCookedWeightGrams * 100
        }
    }

    var carbsPer100g: Double {
        switch self {
        case .local(let f):
            return f.nutritionPer100g?.carbs ?? 0
        case .remote(let p):
            return p.nutriments.carbohydrates100g ?? 0
        case .recipe(let r):
            guard r.totalCookedWeightGrams > 0 else { return 0 }
            return r.totalNutrition.carbs / r.totalCookedWeightGrams * 100
        }
    }

    var fatPer100g: Double {
        switch self {
        case .local(let f):
            return f.nutritionPer100g?.fat ?? 0
        case .remote(let p):
            return p.nutriments.fat100g ?? 0
        case .recipe(let r):
            guard r.totalCookedWeightGrams > 0 else { return 0 }
            return r.totalNutrition.fat / r.totalCookedWeightGrams * 100
        }
    }

    var defaultServing: Double? {
        switch self {
        case .local(let f):   f.defaultServingGrams
        case .remote:         nil
        case .recipe(let r):  r.totalCookedWeightGrams   // Standardportion = ganzes Rezept
        }
    }

    var portions: [FoodPortion] {
        switch self {
        case .local(let f): return f.portions
        default:            return []
        }
    }

    var unit: FoodUnit {
        switch self {
        case .local(let f): return f.unit
        default:            return .grams
        }
    }
}

// MARK: - SuggestionTab

private enum SuggestionTab: Int, CaseIterable {
    case suggestions = 0
    case favorites   = 1
    case templates   = 2

    var label: String {
        switch self {
        case .suggestions: "Vorschläge"
        case .favorites:   "Favoriten"
        case .templates:   "Vorlagen"
        }
    }
}

// MARK: - FoodSearchSheet

struct FoodSearchSheet: View {
    let date: Date
    let meal: MealType

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @Query private var allFoods: [Food]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]
    @Query(sort: \DiaryEntry.loggedAt, order: .reverse) private var recentEntries: [DiaryEntry]

    @Query(filter: #Predicate<Food>   { $0.isFavorite == true }, sort: \Food.name)
    private var favoriteFoods: [Food]
    @Query(filter: #Predicate<Recipe> { $0.isFavorite == true }, sort: \Recipe.name)
    private var favoriteRecipes: [Recipe]
    @Query(sort: \MealTemplate.name) private var allTemplates: [MealTemplate]

    @State private var suggestionTab: SuggestionTab = .suggestions

    @State private var searchText    = ""
    @State private var selection: FoodSelection? = nil
    @State private var grams: Double = 100
    @State private var isLoadingOnline    = false
    @State private var onlineResults: [OFFProduct] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showScanner              = false
    @State private var isLookingUpBarcode       = false
    @State private var barcodeNotFound          = false
    @State private var showCameraPermissionAlert = false
    @State private var showManualEntry    = false
    @State private var portionIdx:        Int    = -1
    @State private var portionCountInt:   Int    = 1
    @State private var portionGramsInt:   Int    = 100
    @State private var useMilliliters:    Bool   = false
    @State private var showAddPortion:    Bool   = false
    @State private var newPortionName:    String = ""
    @State private var newPortionGrams:   String = ""

    private static let gramValues: [Int] = Array(stride(from: 5, through: 2000, by: 5))

    // MARK: - Vorschläge (leeres Suchfeld)

    private var recentFoods: [Food] {
        var seen = Set<PersistentIdentifier>()
        var result: [Food] = []
        for entry in recentEntries {
            guard let food = entry.food, food.source != .recipe, !food.isIngredient else { continue }
            guard seen.insert(food.persistentModelID).inserted else { continue }
            result.append(food)
            if result.count >= 6 { break }
        }
        return result
    }

    private var frequentFoods: [Food] {
        var counts: [PersistentIdentifier: (food: Food, count: Int)] = [:]
        for entry in recentEntries {
            guard let food = entry.food, food.source != .recipe, !food.isIngredient else { continue }
            let pid = food.persistentModelID
            counts[pid] = (food: food, count: (counts[pid]?.count ?? 0) + 1)
        }
        let recentIDs = Set(recentFoods.map(\.persistentModelID))
        return counts.values
            .filter { !recentIDs.contains($0.food.persistentModelID) }
            .sorted { $0.count > $1.count }
            .prefix(5).map(\.food)
    }

    // MARK: - Suchergebnisse

    private var localResults: [Food] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allFoods
            .filter { $0.source != .recipe && !$0.isIngredient && FoodSearch.matches(food: $0, query: q) }
            .sorted { FoodSearch.score(food: $0, query: q) > FoodSearch.score(food: $1, query: q) }
            .prefix(20).map { $0 }
    }

    private var recipeResults: [Recipe] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allRecipes.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            if let sel = selection {
                amountView(sel)
                    .navigationTitle("Menge eingeben")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zurück") { selection = nil }
                        }
                    }
            } else {
                searchListView
                    .navigationTitle(meal.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { dismiss() }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if DataScannerViewController.isSupported {
                                Button {
                                    Task { await requestCameraForScanner() }
                                } label: {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.title3)
                                }
                            }
                        }
                    }
                    .fullScreenCover(isPresented: $showScanner) {
                        BarcodeScannerSheet { code in
                            Task { await handleBarcode(code) }
                        }
                    }
                    .sheet(isPresented: $showManualEntry) {
                        ManualEntrySheet(date: date, meal: meal)
                    }
                    .alert("Produkt nicht gefunden", isPresented: $barcodeNotFound) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Zu diesem Barcode wurde kein Produkt in der Open Food Facts Datenbank gefunden.")
                    }
                    .alert("Kamerazugriff verweigert", isPresented: $showCameraPermissionAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Bitte erlaube den Kamerazugriff in den iOS-Einstellungen unter Datenschutz → Kamera.")
                    }
                    .overlay {
                        if isLookingUpBarcode {
                            ZStack {
                                Color.black.opacity(0.25).ignoresSafeArea()
                                VStack(spacing: 12) {
                                    ProgressView().scaleEffect(1.4).tint(.white)
                                    Text("Produkt wird gesucht…")
                                        .foregroundStyle(.white)
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(24)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
            }
        }
        .interactiveDismissDisabled(selection != nil)
    }

    // MARK: - Suchliste

    private var searchListView: some View {
        List {
            // Tab-Picker (immer sichtbar)
            Section {
                Picker("", selection: $suggestionTab) {
                    ForEach(SuggestionTab.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if suggestionTab == .templates {
                // ── Vorlagen-Tab ──
                templateTabContent

            } else if searchText.isEmpty {
                // ── Vorschläge- oder Favoriten-Tab (kein Suchtext) ──
                if suggestionTab == .favorites {
                    favoritesTabContent
                } else {
                    suggestionsTabContent
                }
            } else {
                // ── Suchergebnisse (Food-Tabs, Suchtext vorhanden) ──
                if localResults.isEmpty && onlineResults.isEmpty && !isLoadingOnline {
                    emptyState
                }
                if !localResults.isEmpty {
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
                }
                if !recipeResults.isEmpty {
                    Section("Meine Rezepte") {
                        ForEach(recipeResults) { recipe in
                            Button { pick(.recipe(recipe)) } label: {
                                FoodResultRow(
                                    name:   recipe.name,
                                    detail: "\(Int(recipe.kcalPer100g)) kcal / 100 g",
                                    badge:  "\(Int(recipe.totalCookedWeightGrams)) g gesamt"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if isLoadingOnline {
                    Section("Open Food Facts") {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Suche online…").foregroundStyle(.secondary).font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                } else if !onlineResults.isEmpty {
                    Section("Open Food Facts") {
                        ForEach(onlineResults) { product in
                            Button { pick(.remote(product)) } label: {
                                FoodResultRow(
                                    name:   product.displayName,
                                    detail: "\(Int(product.nutriments.energyKcal100g ?? 0)) kcal / 100 g",
                                    badge:  product.brandText
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: suggestionTab == .templates ? "Vorlage suchen…" : "Lebensmittel suchen…"
        )
        .onChange(of: searchText) { _, newValue in
            guard suggestionTab != .templates else { return }
            onlineResults = []
            searchTask?.cancel()
            let q = newValue.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                await triggerOnlineSearch(query: q)
            }
        }
        .onChange(of: suggestionTab) { _, _ in
            onlineResults = []
            searchTask?.cancel()
        }
    }

    // MARK: - Tab-Inhalte

    @ViewBuilder
    private var templateTabContent: some View {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty
            ? allTemplates
            : allTemplates.filter { $0.name.localizedCaseInsensitiveContains(q) }

        if filtered.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Keine Vorlagen", systemImage: "doc.on.clipboard")
                } description: {
                    Text("Erstelle Vorlagen im Profil oder über das Menü bei einer Mahlzeit.")
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(filtered) { template in
                    Button { insertTemplate(template) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text("\(template.entries.count) Einträge")
                                Text("·")
                                Text("\(Int(templateKcal(template))) kcal")
                                Text("·")
                                Text(template.mealType.rawValue)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Tippt auf eine Vorlage, um alle Einträge direkt in \(meal.rawValue) einzutragen.")
            }
        }
    }

    @ViewBuilder
    private var favoritesTabContent: some View {
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
    }

    @ViewBuilder
    private var suggestionsTabContent: some View {
        // Zuletzt verwendet als horizontale Chips
        if !recentFoods.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zuletzt verwendet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentFoods) { food in
                                RecentFoodChip(food: food) {
                                    pick(.local(food))
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
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
        Section {
            Button { showManualEntry = true } label: {
                Label("Kalorien frei eingeben", systemImage: "pencil.and.list.clipboard")
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func templateKcal(_ template: MealTemplate) -> Double {
        template.entries.reduce(0.0) { acc, entry in
            guard let f = entry.food else { return acc }
            return acc + f.nutrition(for: entry.grams).kcal
        }
    }

    private func insertTemplate(_ template: MealTemplate) {
        let day = Calendar.current.startOfDay(for: date)
        for entry in template.entries {
            guard let food = entry.food else { continue }
            let diaryEntry = DiaryEntry(date: day, meal: meal, food: food, grams: entry.grams)
            modelContext.insert(diaryEntry)
        }
        try? modelContext.save()
        dismiss()
    }

    private func suggestedFoodRow(_ food: Food) -> some View {
        Button { pick(.local(food)) } label: {
            FoodResultRow(
                name:   food.name,
                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                badge:  food.brand
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mengenansicht

    private func amountView(_ sel: FoodSelection) -> some View {
        let portions = sel.portions
        let eg = effectiveGrams
        let factor = eg / 100.0
        let kcal    = sel.kcalPer100g    * factor
        let protein = sel.proteinPer100g * factor
        let carbs   = sel.carbsPer100g   * factor
        let fat     = sel.fatPer100g     * factor

        return ScrollView {
            VStack(spacing: 20) {
                // Name
                Text(sel.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Makro-Karte (live)
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("\(Int(kcal.rounded()))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                            .monospacedDigit()
                        Text("kcal für \(Int(eg)) \(portionIdx >= 0 ? "g" : (useMilliliters ? "ml" : "g"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack {
                        macroCell("Eiweiß",       value: protein, color: .blue)
                        Spacer()
                        macroCell("Kohlenhydr.",  value: carbs,   color: .orange)
                        Spacer()
                        macroCell("Fett",         value: fat,     color: .yellow)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                // Mengeneingabe
                if !portions.isEmpty {
                    // Zwei Räder: links Anzahl/Gramm, rechts Portionsname
                    HStack(alignment: .center, spacing: 0) {
                        if portionIdx >= 0 {
                            Picker("", selection: $portionCountInt) {
                                ForEach(1...20, id: \.self) { n in Text("\(n)").tag(n) }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 110)

                            Text("×")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        } else {
                            Picker("", selection: $portionGramsInt) {
                                ForEach(Self.gramValues, id: \.self) { v in Text("\(v)").tag(v) }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 160)
                            .onChange(of: portionGramsInt) { _, v in grams = Double(v) }

                            Text(useMilliliters ? "ml" : "g")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }

                        Picker("", selection: $portionIdx) {
                            ForEach(portions.indices, id: \.self) { i in
                                Text(portions[i].name).tag(i)
                            }
                            Text("Gramm").tag(-1)
                        }
                        .pickerStyle(.wheel)
                        .onChange(of: portionIdx) { _, idx in
                            if idx == -1 {
                                portionGramsInt = max(5, min(2000, Int((grams / 5.0).rounded()) * 5))
                            } else {
                                portionCountInt = 1
                            }
                        }
                    }
                    .frame(height: 140)

                    if portionIdx == -1 {
                        Picker("Einheit", selection: $useMilliliters) {
                            Text("g").tag(false)
                            Text("ml").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)

                        if let serving = sel.defaultServing {
                            Button {
                                portionGramsInt = max(5, min(2000, Int((serving / 5.0).rounded()) * 5))
                                grams = Double(portionGramsInt)
                                HapticManager.selection()
                            } label: {
                                Text("Standardportion: \(Int(serving)) \(useMilliliters ? "ml" : "g")")
                                    .font(.subheadline).foregroundStyle(.green)
                            }
                        }
                    }
                } else {
                    WheelAmountPicker(
                        grams: $grams,
                        useMilliliters: $useMilliliters,
                        canToggleUnit: true,
                        defaultServing: sel.defaultServing
                    )
                    .padding(.horizontal)
                }

                Button {
                    confirmEntry(sel)
                } label: {
                    Label("Zum \(meal.rawValue) hinzufügen", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.horizontal)

                // Portion definieren – nur für lokale Foods
                if case .local = sel {
                    Button {
                        newPortionName  = ""
                        newPortionGrams = ""
                        showAddPortion  = true
                    } label: {
                        Label("Portion definieren", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 20)
            .sheet(isPresented: $showAddPortion) {
                if case .local(let food) = sel {
                    AddPortionSheet(food: food, onSave: { newPortion in
                        // Portion-Picker auf neue Portion setzen
                        portionIdx      = food.portions.count - 1
                        portionCountInt = 1
                    })
                }
            }
        }
    }

    private func macroCell(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%.1f g", value))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
    }

    // MARK: - Hilfszustände

    private var searchHint: some View {
        ContentUnavailableView {
            Label("Lebensmittel suchen", systemImage: "magnifyingglass")
        } description: {
            Text("Suche in deiner lokalen Datenbank oder\nfinde Produkte auf Open Food Facts.")
        }
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        ContentUnavailableView.search(text: searchText)
            .listRowBackground(Color.clear)
    }

    private func favoriteSwipeButton(isFavorite: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Label(
                isFavorite ? "Entfernen" : "Favorit",
                systemImage: isFavorite ? "heart.slash.fill" : "heart.fill"
            )
        }
        .tint(isFavorite ? .gray : .pink)
    }

    // MARK: - Aktionen

    /// Tatsächliche Grammzahl — berücksichtigt Portionsauswahl + Anzahl
    private var effectiveGrams: Double {
        guard let sel = selection else { return grams }
        if portionIdx >= 0 && portionIdx < sel.portions.count {
            return sel.portions[portionIdx].grams * Double(portionCountInt)
        }
        return grams
    }

    private func pick(_ sel: FoodSelection) {
        useMilliliters = sel.unit == .milliliters
        if let first = sel.portions.first {
            portionIdx      = 0
            portionCountInt = 1
            grams           = first.grams
        } else {
            portionIdx = -1
            let initial = sel.defaultServing ?? 100
            grams           = initial
            portionGramsInt = max(5, min(2000, Int((initial / 5.0).rounded()) * 5))
        }
        selection = sel
    }

    private func confirmEntry(_ sel: FoodSelection) {
        let finalGrams = effectiveGrams
        let food: Food
        switch sel {
        case .local(let f):
            food = f
        case .recipe(let r):
            food = foodFromRecipe(r)
        case .remote(let p):
            // Duplikat-Check (Online-Suchergebnisse)
            let bcode = p.code ?? ""
            let descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == bcode })
            if !bcode.isEmpty, let existing = try? modelContext.fetch(descriptor).first {
                food = existing
            } else {
                let n = Nutrition(
                    kcal:         p.nutriments.energyKcal100g ?? 0,
                    protein:      p.nutriments.proteins100g ?? 0,
                    carbs:        p.nutriments.carbohydrates100g ?? 0,
                    fat:          p.nutriments.fat100g ?? 0,
                    fiber:        p.nutriments.fiber100g,
                    sugar:        p.nutriments.sugars100g,
                    salt:         p.nutriments.salt100g,
                    saturatedFat: p.nutriments.saturatedFat100g
                )
                food = Food(
                    name:             p.displayName,
                    brand:            p.brandText,
                    barcode:          p.code,
                    source:           .openFoodFacts,
                    nutritionPer100g: n
                )
                modelContext.insert(food)
            }
        }

        let entry = DiaryEntry(date: date, meal: meal, food: food, grams: finalGrams)
        modelContext.insert(entry)
        try? modelContext.save()
        HapticManager.notification(.success)
        dismiss()
    }

    // MARK: - Rezept → Snapshot-Food

    private func foodFromRecipe(_ r: Recipe) -> Food {
        let n100 = r.nutrition(for: 100)
        let nutrition = Nutrition(kcal: n100.kcal, protein: n100.protein,
                                  carbs: n100.carbs, fat: n100.fat)
        let food = Food(name: r.name, source: .recipe, nutritionPer100g: nutrition)
        modelContext.insert(food)
        return food
    }

    @MainActor
    private func requestCameraForScanner() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showScanner = true }
            else { showCameraPermissionAlert = true }
        default:
            showCameraPermissionAlert = true
        }
    }

    @MainActor
    private func handleBarcode(_ code: String) async {
        isLookingUpBarcode = true
        defer { isLookingUpBarcode = false }

        // Erst lokale DB prüfen — schon bekannter Barcode?
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == code })
        if let existing = try? modelContext.fetch(descriptor).first {
            pick(.local(existing))
            return
        }

        do {
            guard let product = try await OpenFoodFactsClient.product(barcode: code) else {
                barcodeNotFound = true
                return
            }
            // Neu: sofort in DB speichern, damit es in der Suche auftaucht
            let n = Nutrition(
                kcal:         product.nutriments.energyKcal100g ?? 0,
                protein:      product.nutriments.proteins100g ?? 0,
                carbs:        product.nutriments.carbohydrates100g ?? 0,
                fat:          product.nutriments.fat100g ?? 0,
                fiber:        product.nutriments.fiber100g,
                sugar:        product.nutriments.sugars100g,
                salt:         product.nutriments.salt100g,
                saturatedFat: product.nutriments.saturatedFat100g
            )
            let food = Food(
                name:             product.displayName,
                brand:            product.brandText,
                barcode:          product.code,
                source:           .openFoodFacts,
                nutritionPer100g: n
            )
            modelContext.insert(food)
            try? modelContext.save()
            pick(.local(food))
        } catch {
            barcodeNotFound = true
        }
    }

    @MainActor
    private func triggerOnlineSearch(query: String) async {
        isLoadingOnline = true
        do {
            onlineResults = try await OpenFoodFactsClient.search(query: query)
        } catch {
            onlineResults = []
        }
        isLoadingOnline = false
    }
}

// MARK: - ManualEntrySheet

struct ManualEntrySheet: View {
    let date: Date
    let meal: MealType

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @State private var name:    String = ""
    @State private var kcal:    Double = 0
    @State private var protein: Double = 0
    @State private var carbs:   Double = 0
    @State private var fat:     Double = 0
    @State private var note:    String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kcal > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezeichnung") {
                    TextField("z. B. Pizza Margherita, Restaurant", text: $name)
                }
                Section("Nährwerte") {
                    HStack {
                        Text("Kalorien")
                        Spacer()
                        TextField("kcal", value: $kcal, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Eiweiß")
                        Spacer()
                        TextField("g", value: $protein, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Kohlenhydrate")
                        Spacer()
                        TextField("g", value: $carbs, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Fett")
                        Spacer()
                        TextField("g", value: $fat, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                Section("Notiz (optional)") {
                    TextField("Kommentar…", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button {
                        save()
                    } label: {
                        Label("Ins Tagebuch eintragen", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(!canSave)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
                .padding(.vertical, 4)
            }
            .navigationTitle("Kalorien eingeben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let entry = DiaryEntry(
            date:          date,
            meal:          meal,
            manualName:    name.trimmingCharacters(in: .whitespaces),
            manualKcal:    kcal,
            manualProtein: protein,
            manualCarbs:   carbs,
            manualFat:     fat
        )
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { entry.note = trimmedNote }
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - WheelAmountPicker

struct WheelAmountPicker: View {
    @Environment(AppTheme.self) private var theme

    @Binding var grams: Double
    @Binding var useMilliliters: Bool
    let defaultServing: Double?

    private static let step   = 5
    private static let maxVal = 2000
    private static let values = Array(stride(from: step, through: maxVal, by: step))

    @State private var pickerVal: Int

    init(grams: Binding<Double>, useMilliliters: Binding<Bool>, canToggleUnit: Bool, defaultServing: Double?) {
        self._grams          = grams
        self._useMilliliters = useMilliliters
        self.defaultServing  = defaultServing
        self._pickerVal      = State(initialValue: Self.snap(grams.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            // g / ml Toggle
            Picker("Einheit", selection: $useMilliliters) {
                Text("g").tag(false)
                Text("ml").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Zahlenrad
            HStack(spacing: 4) {
                Spacer()
                Picker("Menge", selection: $pickerVal) {
                    ForEach(Self.values, id: \.self) { v in
                        Text("\(v)").tag(v)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 160, height: 140)
                .onChange(of: pickerVal) { _, newVal in
                    grams = Double(newVal)
                }

                Text(useMilliliters ? "ml" : "g")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Spacer()
            }
            .onChange(of: grams) { _, newVal in
                let snapped = Self.snap(newVal)
                if snapped != pickerVal { pickerVal = snapped }
            }

            // Standardportion
            if let serving = defaultServing {
                let unit = useMilliliters ? "ml" : "g"
                Button {
                    let snapped = Self.snap(serving)
                    pickerVal = snapped
                    grams     = Double(snapped)
                    HapticManager.selection()
                } label: {
                    Text("Standardportion: \(Int(serving)) \(unit)")
                        .font(.subheadline)
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private static func snap(_ val: Double) -> Int {
        let rounded = Int((val / Double(step)).rounded()) * step
        return max(step, min(maxVal, rounded))
    }
}

// MARK: - AddPortionSheet

struct AddPortionSheet: View {
    let food: Food
    let onSave: (FoodPortion) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    @State private var name:      String = ""
    @State private var gramsText: String = ""

    private static let quickOptions: [(String, Double)] = [
        ("1 Scheibe",   25),
        ("1 Stück",     50),
        ("1 Handvoll",  30),
        ("1 Portion",  150),
        ("1 Glas",     200),
        ("1 Tasse",    240),
        ("1 EL",        15),
        ("1 TL",         5),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Schnellauswahl") {
                    ForEach(Self.quickOptions, id: \.0) { label, grams in
                        Button {
                            name      = label
                            gramsText = "\(Int(grams))"
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int(grams)) g")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                if name == label {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.accent)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                }

                Section("Eigene Portion") {
                    TextField("Name (z. B. 1 Scheibe)", text: $name)
                    HStack {
                        TextField("Gramm", text: $gramsText)
                            .keyboardType(.numberPad)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Portion definieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                              let g = Double(gramsText), g > 0 else { return }
                        let portion = FoodPortion(name: name, grams: g)
                        food.portions.append(portion)
                        onSave(portion)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || Double(gramsText) == nil
                              || (Double(gramsText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - RecentFoodChip

struct RecentFoodChip: View {
    let food: Food
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FoodResultRow

struct FoodResultRow: View {
    let name:   String
    let detail: String
    let badge:  String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium))
                if let badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(detail).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
