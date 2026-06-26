import SwiftUI
import SwiftData

// MARK: - DiaryView (Eltern-View mit Datums-State)

struct DiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiaryEntry.date) private var allEntries: [DiaryEntry]

    @State private var selectedDate:  Date     = .now
    @State private var showSearch:    Bool     = false
    @State private var addingToMeal: MealType  = .breakfast
    @State private var showPhotoMeal: Bool     = false

    @AppStorage("feature.photoRecognition") private var photoRecognitionEnabled = false

    var body: some View {
        NavigationStack {
            DiaryDateContent(date: selectedDate) { meal in
                addingToMeal = meal
                showSearch   = true
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DateNavigatorBar(selectedDate: $selectedDate)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            copyEntries(fromDaysBefore: 1)
                        } label: {
                            Label("Von gestern kopieren", systemImage: "doc.on.doc")
                        }
                        Button {
                            copyEntries(fromDaysBefore: 7)
                        } label: {
                            Label("Von vor einer Woche", systemImage: "doc.on.doc.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if photoRecognitionEnabled {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showPhotoMeal = true } label: {
                            Image(systemName: "sparkles.rectangle.stack")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                FoodSearchSheet(date: selectedDate, meal: addingToMeal)
            }
            .sheet(isPresented: $showPhotoMeal) {
                PhotoMealSheet(date: selectedDate, initialMeal: defaultMealForTime)
            }
        }
    }

    private var defaultMealForTime: MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<20: return .dinner
        default:      return .snack
        }
    }

    private func copyEntries(fromDaysBefore days: Int) {
        HapticManager.notification(.success)
        let cal        = Calendar.current
        let targetDay  = cal.startOfDay(for: selectedDate)
        let sourceDay  = cal.date(byAdding: .day, value: -days, to: targetDay)!
        let sourceEnd  = cal.date(byAdding: .day, value:  1,    to: sourceDay)!

        let source = allEntries.filter { $0.date >= sourceDay && $0.date < sourceEnd }
        for entry in source {
            let copy: DiaryEntry
            if entry.isManual {
                copy = DiaryEntry(
                    date: targetDay, meal: entry.meal,
                    manualName:    entry.manualName    ?? "",
                    manualKcal:    entry.manualKcal    ?? 0,
                    manualProtein: entry.manualProtein ?? 0,
                    manualCarbs:   entry.manualCarbs   ?? 0,
                    manualFat:     entry.manualFat     ?? 0
                )
            } else {
                guard let food = entry.food else { continue }
                copy = DiaryEntry(date: targetDay, meal: entry.meal, food: food, grams: entry.grams)
            }
            copy.note = entry.note
            modelContext.insert(copy)
        }
        try? modelContext.save()
    }
}

// MARK: - DateNavigatorBar

struct DateNavigatorBar: View {
    @Binding var selectedDate: Date
    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 20) {
            Button {
                advance(by: -1)
            } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold)
            }

            Button {
                HapticManager.impact(.light)
                withAnimation(.easeInOut(duration: 0.2)) { selectedDate = .now }
            } label: {
                Text(dateLabel)
                    .font(.headline)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.plain)

            Button {
                advance(by: 1)
            } label: {
                Image(systemName: "chevron.right").fontWeight(.semibold)
            }
        }
    }

    private var dateLabel: String {
        if cal.isDateInToday(selectedDate)     { return "Heute" }
        if cal.isDateInYesterday(selectedDate) { return "Gestern" }
        if cal.isDateInTomorrow(selectedDate)  { return "Morgen" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    private func advance(by days: Int) {
        HapticManager.selection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = cal.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        }
    }
}

// MARK: - DiaryDateContent

/// Separates Kind-View, damit @Query bei jedem Datumswechsel neu mit Predicate initialisiert wird.
struct DiaryDateContent: View {
    let date: Date
    let onAddEntry: (MealType) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var entries:          [DiaryEntry]
    @Query private var yesterdayEntries: [DiaryEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealTemplate.name) private var allTemplates: [MealTemplate]

    @AppStorage("feature.microNutrients")   private var microNutrientsEnabled = false
    @AppStorage("feature.calorieCarryover") private var carryoverEnabled      = false

    @State private var editingEntry: DiaryEntry? = nil
    @State private var showSaveTemplate   = false
    @State private var showInsertTemplate = false
    @State private var activeTemplateMeal: MealType = .breakfast
    @State private var templateName       = ""
    @State private var goalHapticFired    = false

    init(date: Date, onAddEntry: @escaping (MealType) -> Void) {
        self.date       = date
        self.onAddEntry = onAddEntry
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        _entries = Query(
            filter: #Predicate<DiaryEntry> { e in
                e.date >= start && e.date < end
            },
            sort: \DiaryEntry.loggedAt
        )
        let yStart = cal.date(byAdding: .day, value: -1, to: start)!
        _yesterdayEntries = Query(
            filter: #Predicate<DiaryEntry> { e in
                e.date >= yStart && e.date < start
            }
        )
    }

    // Tageswerte
    private var calorieTarget: Int   { profiles.first?.currentCalorieTarget ?? 2000 }

    /// Übertrag vom Vortag: positiv = Bonus (Deficit gestern), negativ = Abzug (Überschuss gestern)
    private var carryoverKcal: Int {
        guard carryoverEnabled else { return 0 }
        let yesterdayKcal = yesterdayEntries.reduce(0.0) { $0 + $1.kcal }
        guard yesterdayKcal > 0 else { return 0 }   // kein Log gestern → kein Übertrag
        let delta = Double(calorieTarget) - yesterdayKcal
        return Int(min(500, max(-500, delta)).rounded())
    }

    private var adjustedTarget: Int { calorieTarget + carryoverKcal }
    // Mikronährstoff-Ziele aus Profil (nil = nicht gesetzt)
    private var microFiberGoal:       Double? { profiles.first?.fiberGoalG }
    private var microSugarGoal:       Double? { profiles.first?.sugarGoalG }
    private var microSatFatGoal:      Double? { profiles.first?.saturatedFatGoalG }
    private var microSaltGoal:        Double? { profiles.first?.saltGoalG }
    private var totalKcal:    Double { entries.reduce(0) { $0 + $1.kcal } }
    private var totalProtein: Double { entries.reduce(0) { $0 + $1.protein } }
    private var totalCarbs:   Double { entries.reduce(0) { $0 + $1.carbs   } }
    private var totalFat:     Double { entries.reduce(0) { $0 + $1.fat     } }

    // Mikronährstoffe (nur wenn Daten vorhanden)
    private var totalFiber: Double {
        entries.reduce(0) { acc, e in
            guard let n = e.food?.nutritionPer100g, let f = n.fiber else { return acc }
            return acc + f * e.grams / 100.0
        }
    }
    private var totalSugar: Double {
        entries.reduce(0) { acc, e in
            guard let n = e.food?.nutritionPer100g, let s = n.sugar else { return acc }
            return acc + s * e.grams / 100.0
        }
    }
    private var totalSalt: Double {
        entries.reduce(0) { acc, e in
            guard let n = e.food?.nutritionPer100g, let s = n.salt else { return acc }
            return acc + s * e.grams / 100.0
        }
    }
    private var totalSaturatedFat: Double {
        entries.reduce(0) { acc, e in
            guard let n = e.food?.nutritionPer100g, let s = n.saturatedFat else { return acc }
            return acc + s * e.grams / 100.0
        }
    }
    private var hasMicroData: Bool {
        totalFiber > 0 || totalSugar > 0 || totalSalt > 0 || totalSaturatedFat > 0
    }

    // Makroziele aus Profil-Split berechnen
    private var macroSplit: MacroSplit { profiles.first?.currentMacroSplit ?? MacroSplit() }
    private var proteinTargetG: Double { Double(calorieTarget) * macroSplit.proteinPercent / 100.0 / 4.0 }
    private var carbsTargetG:   Double { Double(calorieTarget) * macroSplit.carbsPercent   / 100.0 / 4.0 }
    private var fatTargetG:     Double { Double(calorieTarget) * macroSplit.fatPercent      / 100.0 / 9.0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CalorieSummaryCard(
                    consumed: totalKcal,
                    target:   adjustedTarget,
                    carryoverKcal: carryoverKcal,
                    protein:  totalProtein,
                    carbs:    totalCarbs,
                    fat:      totalFat,
                    proteinTarget: proteinTargetG,
                    carbsTarget:   carbsTargetG,
                    fatTarget:     fatTargetG,
                    fiber:         (microNutrientsEnabled && hasMicroData) ? totalFiber        : nil,
                    sugar:         (microNutrientsEnabled && hasMicroData) ? totalSugar        : nil,
                    salt:          (microNutrientsEnabled && hasMicroData) ? totalSalt         : nil,
                    saturatedFat:  (microNutrientsEnabled && hasMicroData) ? totalSaturatedFat : nil,
                    fiberGoal:        microNutrientsEnabled ? microFiberGoal  : nil,
                    sugarGoal:        microNutrientsEnabled ? microSugarGoal  : nil,
                    saltGoal:         microNutrientsEnabled ? microSaltGoal   : nil,
                    saturatedFatGoal: microNutrientsEnabled ? microSatFatGoal : nil
                )

                WaterCard(date: date)

                ForEach(MealType.allCases, id: \.self) { meal in
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
                            activeTemplateMeal = meal
                            showInsertTemplate = true
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: totalKcal) { oldVal, newVal in
            // Haptic wenn Tagesziel zum ersten Mal überschritten wird
            if !goalHapticFired && oldVal < Double(calorieTarget) && newVal >= Double(calorieTarget) {
                HapticManager.notification(.success)
                goalHapticFired = true
            }
            // Reset wenn wieder deutlich darunter (z.B. Eintrag gelöscht)
            if newVal < Double(calorieTarget) * 0.9 {
                goalHapticFired = false
            }
        }
        .sheet(item: $editingEntry) { DiaryEntryEditSheet(entry: $0) }
        .sheet(isPresented: $showSaveTemplate) {
            SaveTemplateSheet(
                meal:        activeTemplateMeal,
                entries:     entries.filter { $0.meal == activeTemplateMeal },
                initialName: templateName
            )
        }
        .sheet(isPresented: $showInsertTemplate) {
            InsertTemplateSheet(
                templates: allTemplates,
                date:      date,
                meal:      activeTemplateMeal
            )
        }
    }

    private func deleteEntry(_ entry: DiaryEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}

// MARK: - CalorieSummaryCard

struct CalorieSummaryCard: View {
    @Environment(AppTheme.self) private var theme

    let consumed: Double
    let target:   Int
    var carryoverKcal: Int = 0   // Übertrag vom Vortag (+Bonus / -Abzug)
    let protein:  Double
    let carbs:    Double
    let fat:      Double
    var proteinTarget: Double  = 0
    var carbsTarget:   Double  = 0
    var fatTarget:     Double  = 0
    var fiber:        Double? = nil
    var sugar:        Double? = nil
    var salt:         Double? = nil
    var saturatedFat: Double? = nil
    // Optionale Tagesziele für Mikronährstoffe
    var fiberGoal:        Double? = nil
    var sugarGoal:        Double? = nil
    var saltGoal:         Double? = nil
    var saturatedFatGoal: Double? = nil

    private var progress: Double   { min(1.0, consumed / Double(max(1, target))) }
    private var remaining: Int     { target - Int(consumed.rounded()) }
    private var isOverBudget: Bool { remaining < 0 }

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

    @State private var animatedProgress: Double = 0
    @State private var hasAppeared: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Kalorienring
                ZStack {
                    Circle()
                        .stroke(ringColor.opacity(0.15), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(ringColor,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.6), value: animatedProgress)
                    VStack(spacing: 0) {
                        Text("\(Int(consumed))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(ringColor)
                            .monospacedDigit()
                            .animation(.spring(duration: 0.4), value: ringColor)
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .onAppear {
                    if hasAppeared {
                        // Tab-Wechsel: direkt setzen ohne Animation
                        animatedProgress = progress
                    } else {
                        hasAppeared = true
                        withAnimation(.spring(duration: 0.6)) {
                            animatedProgress = progress
                        }
                    }
                }
                .onChange(of: progress) { _, newVal in
                    withAnimation(.spring(duration: 0.4)) {
                        animatedProgress = newVal
                    }
                }

                // Zahlen-Spalte
                VStack(alignment: .leading, spacing: 7) {
                    summaryLine("Ziel",
                                value: "\(target) kcal",
                                color: .primary)
                    if carryoverKcal != 0 {
                        summaryLine("Übertrag",
                                    value: "\(carryoverKcal > 0 ? "+" : "")\(carryoverKcal) kcal",
                                    color: carryoverKcal > 0 ? theme.accent.opacity(0.85) : Color.red.opacity(0.85))
                    }
                    summaryLine("Gegessen",
                                value: "\(Int(consumed)) kcal",
                                color: ringColor)
                    summaryLine(isOverBudget ? "Überschuss" : "Verbleibend",
                                value: "\(abs(remaining)) kcal",
                                color: isOverBudget ? .red : .secondary)
                }

                Spacer(minLength: 0)
            }

            Divider()

            // Makros mit Fortschrittsbalken
            HStack(alignment: .top) {
                macroCell("Protein",     value: protein, target: proteinTarget, color: theme.protein)
                Spacer()
                macroCell("Kohlenhydr.", value: carbs,   target: carbsTarget,   color: theme.carbs)
                Spacer()
                macroCell("Fett",        value: fat,     target: fatTarget,     color: theme.fat)
            }

            // Mikronährstoffe (nur wenn vorhanden)
            if fiber != nil || sugar != nil || salt != nil || saturatedFat != nil {
                Divider()
                VStack(spacing: 6) {
                    if let v = fiber        { microRow("Ballaststoffe",   value: v, goal: fiberGoal) }
                    if let v = sugar        { microRow("davon Zucker",    value: v, goal: sugarGoal) }
                    if let v = saturatedFat { microRow("ges. Fettsäuren", value: v, goal: saturatedFatGoal) }
                    if let v = salt         { microRow("Salz",            value: v, goal: saltGoal) }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    cardTintColor.opacity(0.10),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.4), value: cardTintColor)
    }

    private func summaryLine(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 130)
    }

    private func macroCell(_ name: String, value: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value)) g")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Fortschrittsbalken
            if target > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.18))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(value > target ? 1.0 : 0.75))
                            .frame(width: min(geo.size.width, geo.size.width * value / max(1, target)),
                                   height: 8)
                            .animation(.spring(duration: 0.4), value: value)
                    }
                }
                .frame(height: 8)
                Text("/ \(Int(target)) g")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 70)
    }

    private func microRow(_ label: String, value: Double, goal: Double? = nil) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let g = goal {
                    Text(String(format: value >= 10 ? "%.0f / %.0f g" : "%.1f / %.0f g", value, g))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Text(String(format: value >= 10 ? "%.0f g" : "%.1f g", value))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if let g = goal, g > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.purple.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(value > g ? Color.red.opacity(0.7) : Color.purple.opacity(0.6))
                            .frame(width: min(geo.size.width, geo.size.width * value / max(1, g)), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

// MARK: - WaterCard

struct WaterCard: View {
    let date: Date

    @Environment(AppTheme.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var logs:     [WaterLog]

    init(date: Date) {
        self.date = date
        let start = Calendar.current.startOfDay(for: date)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        _logs = Query(filter: #Predicate<WaterLog> { l in l.date >= start && l.date < end })
    }

    private var mlConsumed: Double { logs.first?.mlConsumed ?? 0 }
    private var mlGoal:     Double { profiles.first?.waterGoalMl ?? 2000 }
    private var progress:   Double { min(1.0, mlConsumed / max(1, mlGoal)) }
    private var glassesLeft: Int   { max(0, Int(((mlGoal - mlConsumed) / 250).rounded(.up))) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Wasser", systemImage: "drop.fill")
                    .font(.headline).foregroundStyle(theme.water)
                Spacer()
                Text(String(format: "%.0f / %.0f ml", mlConsumed, mlGoal))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.water.opacity(0.12))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.water.opacity(progress >= 1 ? 1.0 : 0.65))
                        .frame(width: geo.size.width * progress, height: 10)
                        .animation(.spring(duration: 0.4), value: progress)
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                waterButton("+150 ml", ml: 150)
                waterButton("+250 ml", ml: 250)
                waterButton("+500 ml", ml: 500)
                Spacer()
                if mlConsumed > 0 {
                    Button { add(ml: -250) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            if progress < 1 {
                Text("Noch \(glassesLeft) Gläser bis zum Ziel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Label("Tagesziel erreicht!", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(theme.water)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func waterButton(_ label: String, ml: Double) -> some View {
        Button { add(ml: ml) } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.water.opacity(0.12))
                .foregroundStyle(theme.water)
                .clipShape(Capsule())
        }
    }

    private func add(ml: Double) {
        HapticManager.impact(ml < 0 ? .light : .light)
        let start = Calendar.current.startOfDay(for: date)
        if let log = logs.first {
            log.mlConsumed = max(0, log.mlConsumed + ml)
        } else {
            guard ml > 0 else { return }
            let log = WaterLog(date: start, mlConsumed: ml)
            modelContext.insert(log)
        }
        try? modelContext.save()
    }
}

// MARK: - MealSectionCard

struct MealSectionCard: View {
    @Environment(AppTheme.self) private var theme

    let meal:     MealType
    let entries:  [DiaryEntry]
    let onAdd:    () -> Void
    let onDelete: (DiaryEntry) -> Void
    let onEdit:   (DiaryEntry) -> Void
    let onSaveAsTemplate: () -> Void
    let onInsertTemplate: () -> Void

    private var totalKcal: Double { entries.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        VStack(spacing: 0) {
            // Header-Zeile
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: mealIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mealColor)
                        .padding(6)
                        .background(mealColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(meal.rawValue)
                        .font(.headline)
                }
                Spacer()
                if !entries.isEmpty {
                    Text("\(Int(totalKcal)) kcal")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Einträge
            if entries.isEmpty {
                Button(action: onAdd) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.title3)
                            .foregroundStyle(mealColor.opacity(0.45))
                        Text(emptyPrompt)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            } else {
                Divider().padding(.leading, 16)
                ForEach(entries) { entry in
                    EntryRow(
                        entry:    entry,
                        onDelete: { onDelete(entry) },
                        onEdit:   { onEdit(entry) }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal:   .opacity
                    ))
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
                .animation(.spring(duration: 0.3), value: entries.count)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var mealIcon: String {
        switch meal {
        case .breakfast: "sunrise.fill"
        case .lunch:     "sun.max.fill"
        case .dinner:    "moon.stars.fill"
        case .snack:     "leaf.fill"
        }
    }

    private var mealColor: Color {
        switch meal {
        case .breakfast: .orange
        case .lunch:     .yellow
        case .dinner:    .indigo
        case .snack:     .green
        }
    }

    private var emptyPrompt: String {
        switch meal {
        case .breakfast: "Frühstück eintragen…"
        case .lunch:     "Mittagessen eintragen…"
        case .dinner:    "Abendessen eintragen…"
        case .snack:     "Snack eintragen…"
        }
    }
}

// MARK: - EntryRow

struct EntryRow: View {
    let entry:    DiaryEntry
    let onDelete: () -> Void
    let onEdit:   () -> Void

    /// Dominant macro color based on kcal contribution
    private var macroColor: Color {
        let p = entry.protein * 4.0
        let c = entry.carbs   * 4.0
        let f = entry.fat     * 9.0
        guard p + c + f > 0 else { return .gray }
        if p >= c && p >= f { return .blue }
        if c >= p && c >= f { return .orange }
        return .yellow
    }

    var body: some View {
        HStack(spacing: 0) {
            // Farbiger Makro-Streifen links
            macroColor
                .opacity(0.7)
                .frame(width: 3)
                .clipShape(Capsule())
                .padding(.vertical, 8)
                .padding(.leading, 10)

            // Inhalt
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.displayName)
                            .font(.subheadline.weight(.medium))
                        if entry.note != nil {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if entry.isManual {
                        Text("Manuelle Eingabe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(entry.grams)) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int(entry.kcal)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.blue.opacity(0.7))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red.opacity(0.7))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - DiaryEntryEditSheet

struct DiaryEntryEditSheet: View {
    let entry: DiaryEntry

    @Environment(AppTheme.self)   private var theme
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss

    @State private var grams:           Double
    @State private var useMilliliters:  Bool
    @State private var meal:            MealType
    @State private var date:            Date
    @State private var note:            String
    // Felder für manuelle Einträge
    @State private var manualName:      String
    @State private var manualKcal:      Double
    @State private var manualProtein:   Double
    @State private var manualCarbs:     Double
    @State private var manualFat:       Double

    init(entry: DiaryEntry) {
        self.entry = entry
        _grams           = State(initialValue: entry.grams)
        _useMilliliters  = State(initialValue: entry.food?.unit == .milliliters)
        _meal            = State(initialValue: entry.meal)
        _date            = State(initialValue: entry.date)
        _note            = State(initialValue: entry.note ?? "")
        _manualName      = State(initialValue: entry.manualName    ?? "")
        _manualKcal      = State(initialValue: entry.manualKcal    ?? 0)
        _manualProtein   = State(initialValue: entry.manualProtein ?? 0)
        _manualCarbs     = State(initialValue: entry.manualCarbs   ?? 0)
        _manualFat       = State(initialValue: entry.manualFat     ?? 0)
    }

    private var kcalPreview: Int {
        if entry.isManual { return Int(manualKcal.rounded()) }
        guard let food = entry.food else { return 0 }
        return Int(food.nutrition(for: grams).kcal.rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                if entry.isManual {
                    // Manuelle Eingabe: Name + Makros editierbar
                    Section("Bezeichnung") {
                        TextField("z. B. Pizza Margherita", text: $manualName)
                    }
                    Section("Nährwerte") {
                        HStack {
                            Text("Kalorien")
                            Spacer()
                            TextField("kcal", value: $manualKcal, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("kcal").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Eiweiß")
                            Spacer()
                            TextField("g", value: $manualProtein, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("g").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Kohlenhydrate")
                            Spacer()
                            TextField("g", value: $manualCarbs, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("g").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Fett")
                            Spacer()
                            TextField("g", value: $manualFat, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Lebensmittel", value: entry.food?.name ?? "?")
                        LabeledContent("Kalorien", value: "\(kcalPreview) kcal")
                            .foregroundStyle(theme.accent)
                    }
                    Section("Menge") {
                        WheelAmountPicker(
                            grams:          $grams,
                            useMilliliters: $useMilliliters,
                            canToggleUnit:  true,
                            defaultServing: entry.food?.defaultServingGrams
                        )
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                    }
                }

                Section("Mahlzeit") {
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Datum") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                Section("Notiz") {
                    TextField("Optional…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Eintrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        entry.meal = meal
        entry.date = date
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        if entry.isManual {
            entry.manualName    = manualName
            entry.manualKcal    = manualKcal
            entry.manualProtein = manualProtein
            entry.manualCarbs   = manualCarbs
            entry.manualFat     = manualFat
        } else {
            entry.grams = grams
        }
        try? modelContext.save()
        dismiss()
    }
}

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
