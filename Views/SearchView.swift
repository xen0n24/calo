import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

// MARK: - SearchTab

private enum SearchTab: String, CaseIterable {
    case foods   = "Lebensmittel"
    case recipes = "Rezepte"
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(AppTheme.self)  private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var allFoods: [Food]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]
    @Query(sort: \DiaryEntry.loggedAt, order: .reverse) private var allEntries: [DiaryEntry]

    @State private var searchTab: SearchTab = .foods
    @State private var searchText           = ""
    @State private var isLoadingOnline      = false
    @State private var onlineResults: [OFFProduct] = []
    @State private var searchTask: Task<Void, Never>? = nil

    // Sheets – Lebensmittel
    @State private var selectedFood:          Food? = nil
    @State private var showScanner                  = false
    @State private var showCameraPermissionAlert    = false
    @State private var showCustomFoodEditor         = false
    @State private var editingFood:           Food? = nil

    // Sheets – Rezepte
    @State private var detailRecipe: Recipe?  = nil
    @State private var editingRecipe: Recipe? = nil
    @State private var showRecipeEditor       = false

    // MARK: - Vorschläge aus Nutzungshistorie

    /// Zuletzt geloggte eindeutige Lebensmittel (max. 5)
    private var recentFoods: [Food] {
        var seen  = Set<PersistentIdentifier>()
        var result: [Food] = []
        for entry in allEntries {
            guard let food = entry.food, food.source != .recipe, !food.isIngredient else { continue }
            guard seen.insert(food.persistentModelID).inserted else { continue }
            result.append(food)
            if result.count >= 5 { break }
        }
        return result
    }

    /// Häufigste Lebensmittel (max. 5, ohne die aus recentFoods)
    private var frequentFoods: [Food] {
        var counts: [PersistentIdentifier: (food: Food, count: Int)] = [:]
        for entry in allEntries {
            guard let food = entry.food, food.source != .recipe, !food.isIngredient else { continue }
            let pid = food.persistentModelID
            counts[pid] = (food: food, count: (counts[pid]?.count ?? 0) + 1)
        }
        let recentIDs = Set(recentFoods.map { $0.persistentModelID })
        return counts.values
            .filter { !recentIDs.contains($0.food.persistentModelID) }
            .sorted { $0.count > $1.count }
            .prefix(5).map { $0.food }
    }

    // MARK: Gefiltert

    private var localFoods: [Food] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allFoods
            .filter { $0.source != .recipe && !$0.isIngredient && FoodSearch.matches(food: $0, query: q) }
            .sorted { FoodSearch.score(food: $0, query: q) > FoodSearch.score(food: $1, query: q) }
            .prefix(20).map { $0 }
    }

    private var filteredRecipes: [Recipe] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return allRecipes }
        return allRecipes.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                // Segment-Picker (immer oben)
                Section {
                    Picker("", selection: $searchTab) {
                        ForEach(SearchTab.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                // Inhalt: direkte ForEach-Zeilen, KEIN verschachteltes List
                if searchTab == .foods {
                    foodSections
                } else {
                    recipeSections
                }
            }
            .navigationTitle("Suche")
            .searchable(
                text: $searchText,
                prompt: searchTab == .foods ? "Lebensmittel suchen…" : "Rezept suchen…"
            )
            .onChange(of: searchText) { _, newValue in
                guard searchTab == .foods else { return }
                onlineResults = []
                searchTask?.cancel()
                let q = newValue.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { return }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    guard !Task.isCancelled else { return }
                    await searchOnline(query: q)
                }
            }
            .onChange(of: searchTab) { _, _ in
                onlineResults = []
                searchTask?.cancel()
            }
            .toolbar {
                if searchTab == .recipes {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showRecipeEditor = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                } else {
                    // Lebensmittel: eigenes erstellen + Barcode
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCustomFoodEditor = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                    if DataScannerViewController.isSupported {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { Task { await requestCameraForScanner() } } label: {
                                Image(systemName: "barcode.viewfinder")
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedFood)     { FoodDetailSheet(food: $0) }
            .sheet(isPresented: $showRecipeEditor) { RecipeEditorView() }
            .sheet(item: $editingRecipe)    { RecipeEditorView(recipe: $0) }
            .sheet(item: $detailRecipe)     { RecipeDetailSheet(recipe: $0) }
            .sheet(isPresented: $showCustomFoodEditor) {
                CustomFoodSheet { newFood in selectedFood = newFood }
            }
            .sheet(item: $editingFood) { CustomFoodSheet(food: $0) }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerSheet { code in Task { await handleBarcode(code) } }
            }
            .alert("Kamerazugriff verweigert", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Bitte erlaube den Kamerazugriff in den iOS-Einstellungen unter Datenschutz → Kamera.")
            }
        }
    }

    // MARK: - Lebensmittel-Sektionen

    @ViewBuilder
    private var foodSections: some View {
        if searchText.isEmpty {
            if !recentFoods.isEmpty {
                Section("Zuletzt verwendet") {
                    ForEach(recentFoods) { foodRow($0) }
                }
            }
            if !frequentFoods.isEmpty {
                Section("Häufig verwendet") {
                    ForEach(frequentFoods) { foodRow($0) }
                }
            }
            if recentFoods.isEmpty && frequentFoods.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Noch keine Einträge", systemImage: "clock")
                    } description: {
                        Text("Sobald du Lebensmittel ins Tagebuch einträgst, erscheinen sie hier.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }

        if !localFoods.isEmpty || isLoadingOnline || !onlineResults.isEmpty {
            Section {
                ForEach(localFoods) { foodRow($0) }

                if isLoadingOnline {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Suche online…").foregroundStyle(.secondary).font(.subheadline)
                    }
                } else {
                    ForEach(onlineResults) { product in
                        Button { addAndSelect(product) } label: {
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
        } else if !searchText.isEmpty && localFoods.isEmpty && !isLoadingOnline {
            Section {
                ContentUnavailableView {
                    Label("Keine Ergebnisse", systemImage: "magnifyingglass")
                } description: {
                    Text("Kein Lebensmittel gefunden für „\(searchText)".")
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func foodRow(_ food: Food) -> some View {
        Button { selectedFood = food } label: {
            FoodResultRow(
                name:   food.name,
                detail: "\(Int(food.nutritionPer100g?.kcal ?? 0)) kcal / 100 g",
                badge:  food.brand
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            favoriteSwipeButton(isFavorite: food.isFavorite) {
                food.isFavorite.toggle()
                try? modelContext.save()
            }
        }
        .swipeActions(edge: .trailing) {
            if food.source == .custom {
                Button(role: .destructive) { deleteFood(food) } label: {
                    Label("Löschen", systemImage: "trash")
                }
                Button { editingFood = food } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }

    // MARK: - Rezept-Sektionen (kein verschachteltes List!)

    @ViewBuilder
    private var recipeSections: some View {
        if allRecipes.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Keine Rezepte", systemImage: "fork.knife")
                } description: {
                    Text("Erstelle dein erstes Rezept mit dem + Button.")
                } actions: {
                    Button("Rezept erstellen") { showRecipeEditor = true }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(filteredRecipes) { recipe in
                    Button { detailRecipe = recipe } label: {
                        RecipeRow(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        favoriteSwipeButton(isFavorite: recipe.isFavorite) {
                            recipe.isFavorite.toggle()
                            try? modelContext.save()
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleteRecipe(recipe) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button { editingRecipe = recipe } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Aktionen

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

    private func addAndSelect(_ product: OFFProduct) {
        if let barcode = product.code,
           let existing = allFoods.first(where: { $0.barcode == barcode }) {
            selectedFood = existing
            return
        }
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
        let food = Food(name: product.displayName, brand: product.brandText,
                        barcode: product.code, source: .openFoodFacts, nutritionPer100g: n)
        modelContext.insert(food)
        try? modelContext.save()
        selectedFood = food
    }

    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
    }

    private func deleteFood(_ food: Food) {
        modelContext.delete(food)
        try? modelContext.save()
    }

    @MainActor
    private func handleBarcode(_ code: String) async {
        do {
            if let product = try await OpenFoodFactsClient.product(barcode: code) {
                addAndSelect(product)
            }
        } catch { }
    }

    @MainActor
    private func searchOnline(query: String) async {
        isLoadingOnline = true
        do { onlineResults = try await OpenFoodFactsClient.search(query: query) }
        catch { onlineResults = [] }
        isLoadingOnline = false
    }

    private func favoriteSwipeButton(isFavorite: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(
                isFavorite ? "Entfernen" : "Favorit",
                systemImage: isFavorite ? "heart.slash.fill" : "heart.fill"
            )
        }
        .tint(isFavorite ? .gray : .pink)
    }
}

// MARK: - FoodDetailSheet

struct FoodDetailSheet: View {
    let food: Food

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @State private var grams:        Double    = 100
    @State private var portionIdx:   Int       = -1
    @State private var portionCount: Double    = 1.0
    @State private var selectedMeal: MealType  = .breakfast
    @State private var selectedDate: Date      = .now

    private var n: Nutrition? { food.nutritionPer100g }
    private var effectiveGrams: Double {
        if portionIdx >= 0 && portionIdx < food.portions.count {
            return food.portions[portionIdx].grams * portionCount
        }
        return grams
    }
    private var factor: Double { effectiveGrams / 100.0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(Int((n?.kcal ?? 0) * factor))")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent)
                            Text("kcal für \(Int(effectiveGrams)) \(food.unit.rawValue)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Menge") {
                    if !food.portions.isEmpty {
                        Picker("Portion", selection: $portionIdx) {
                            ForEach(food.portions.indices, id: \.self) { i in
                                Text("\(food.portions[i].name) · \(Int(food.portions[i].grams)) g").tag(i)
                            }
                            Text("Eigene Menge").tag(-1)
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 130)

                        if portionIdx >= 0 {
                            HStack {
                                Text("Anzahl")
                                Spacer()
                                NumericStepperView(value: $portionCount, range: 0.5...20, step: 0.5, unit: "×")
                            }
                        } else {
                            NumericStepperView(value: $grams, range: 1...5_000, step: 5, unit: food.unit.rawValue)
                        }
                    } else {
                        NumericStepperView(value: $grams, range: 1...5_000, step: 5, unit: food.unit.rawValue)
                        if let serving = food.defaultServingGrams {
                            Button("Standardportion: \(Int(serving)) \(food.unit.rawValue)") { grams = serving }
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
                .onChange(of: portionIdx) { _, idx in
                    if idx >= 0 && idx < food.portions.count {
                        grams = food.portions[idx].grams * portionCount
                    }
                }
                .onChange(of: portionCount) { _, count in
                    if portionIdx >= 0 && portionIdx < food.portions.count {
                        grams = food.portions[portionIdx].grams * count
                    }
                }

                Section("Nährwerte pro Portion") {
                    nutriRow("Kalorien",      value: (n?.kcal ?? 0) * factor,    unit: "kcal")
                    nutriRow("Eiweiß",        value: (n?.protein ?? 0) * factor, unit: "g")
                    nutriRow("Kohlenhydrate", value: (n?.carbs ?? 0) * factor,   unit: "g")
                    nutriRow("Fett",          value: (n?.fat ?? 0) * factor,     unit: "g")
                    if let fiber = n?.fiber {
                        nutriRow("Ballaststoffe",     value: fiber * factor,      unit: "g")
                    }
                    if let sugar = n?.sugar {
                        nutriRow("davon Zucker",      value: sugar * factor,      unit: "g")
                    }
                    if let sat = n?.saturatedFat {
                        nutriRow("davon ges. Fette",  value: sat * factor,        unit: "g")
                    }
                    if let salt = n?.salt {
                        nutriRow("Salz",              value: salt * factor,       unit: "g")
                    }
                }

                Section("Ins Tagebuch eintragen") {
                    DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                    Picker("Mahlzeit", selection: $selectedMeal) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button { addToDiary() } label: {
                        Label("Hinzufügen", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity).font(.headline)
                    }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        food.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: food.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(food.isFavorite ? .pink : .secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                if !food.portions.isEmpty {
                    portionIdx = 0
                    grams = food.portions[0].grams
                }
            }
        }
    }

    private func nutriRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            Text("\(String(format: value >= 10 ? "%.0f" : "%.1f", value)) \(unit)")
                .foregroundStyle(.secondary).fontWeight(.medium)
        }
    }

    private func addToDiary() {
        let entry = DiaryEntry(date: selectedDate, meal: selectedMeal, food: food, grams: effectiveGrams)
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

// @Model macht Food bereits Identifiable – keine Extension nötig
