import SwiftUI
import SwiftData
import Charts

// MARK: - StatsView

struct StatsView: View {
    @Environment(AppTheme.self)  private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \DiaryEntry.date,  order: .reverse) private var diaryEntries:  [DiaryEntry]
    @Query private var profiles: [UserProfile]

    @AppStorage("feature.bodyMeasurements")       private var bodyMeasurementsEnabled  = false
    @AppStorage("bodyMeasurements.displayMode")   private var measurementDisplayMode   = "separate"
    @Query(sort: \BodyMeasurementType.sortOrder)  private var measurementTypes: [BodyMeasurementType]
    @Query(sort: \BodyMeasurement.date)           private var allBodyMeasurements: [BodyMeasurement]

    @State private var showWeightLogger           = false
    @State private var measurementLogRequest:     MeasurementLogRequest? = nil
    @State private var showAddMeasurementType     = false
    @State private var newMeasurementName         = ""
    @State private var newMeasurementUnit         = ""
    @State private var showGroupManager           = false

    private var profile: UserProfile? { profiles.first }
    private var calorieTarget: Int { profile?.currentCalorieTarget ?? 2000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    streakSection
                    weightSection
                    weightPredictionSection
                    calorieSection
                    if let profile {
                        tdeeSection(profile)
                        adaptiveSection(profile)
                    }
                    if bodyMeasurementsEnabled {
                        bodyMeasurementsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistiken")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showWeightLogger = true
                    } label: {
                        Label("Gewicht eintragen", systemImage: "scalemass.fill")
                    }
                }
            }
            .sheet(isPresented: $showWeightLogger) {
                WeightLoggerSheet()
            }
            .sheet(item: $measurementLogRequest) { request in
                BodyMeasurementLoggerSheet(types: measurementTypes, initialType: request.initialType)
            }
            .sheet(isPresented: $showAddMeasurementType) {
                AddMeasurementTypeSheet(
                    name: $newMeasurementName,
                    unit: $newMeasurementUnit
                ) {
                    let t = BodyMeasurementType(
                        name:      newMeasurementName.trimmingCharacters(in: .whitespaces),
                        unit:      newMeasurementUnit.trimmingCharacters(in: .whitespaces),
                        sortOrder: measurementTypes.count
                    )
                    modelContext.insert(t)
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $showGroupManager) {
                GroupManagerSheet()
            }
        }
    }

    // MARK: - Karten-Helper

    private func statCard<Content: View>(
        header: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func statRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(valueColor).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }

    // MARK: - Streak

    @ViewBuilder
    private var streakSection: some View {
        let streak = loggingStreak
        if streak > 0 {
            statCard(header: "Logging-Streak") {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(streak >= 7 ? Color.orange : theme.accent.opacity(0.15))
                            .frame(width: 56, height: 56)
                        VStack(spacing: 0) {
                            Text("\(streak)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(streak >= 7 ? Color.white : theme.accent)
                            Text("Tage")
                                .font(.caption2)
                                .foregroundStyle(streak >= 7 ? Color.white.opacity(0.85) : theme.accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(streakTitle(streak))
                            .font(.headline)
                        Text(streakSubtitle(streak))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var loggingStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var date   = cal.startOfDay(for: Date())
        while true {
            let next = cal.date(byAdding: .day, value: 1, to: date)!
            if diaryEntries.contains(where: { $0.date >= date && $0.date < next }) {
                streak += 1
            } else {
                break
            }
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }

    private func streakTitle(_ n: Int) -> String {
        switch n {
        case 1:        return "Erster Tag!"
        case 2...6:    return "\(n) Tage in Folge"
        case 7...13:   return "Eine Woche am Stück 🔥"
        case 14...29:  return "\(n) Tage – beeindruckend!"
        default:       return "\(n) Tage – du bist unaufhaltbar!"
        }
    }

    private func streakSubtitle(_ n: Int) -> String {
        n == 1 ? "Bleib dran!" : "Jeden Tag eingetragen"
    }

    // MARK: - Gewicht

    @ViewBuilder
    private var weightSection: some View {
        statCard(header: "Gewicht") {
            if weightEntries.isEmpty {
                emptyHint(
                    icon: "scalemass",
                    text: "Noch kein Gewicht eingetragen.\nTippe oben rechts auf die Waage."
                )
            } else {
                // Aktuelles Gewicht
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aktuell")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f kg", weightEntries[0].weightKg))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    if weightEntries.count >= 2 {
                        let delta = weightEntries[0].weightKg - weightEntries[1].weightKg
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("vs. letztes Mal")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%+.1f kg", delta))
                                .font(.headline)
                                .foregroundStyle(delta <= 0 ? theme.accent : Color.red)
                        }
                    }
                }
                .padding(.bottom, 12)

                // Gewichtsverlauf Chart (letzte 90 Tage) — vollbreit
                let chartData = weightChartData
                if chartData.count >= 2 {
                    Chart(chartData) { entry in
                        LineMark(
                            x: .value("Datum",   entry.date),
                            y: .value("Gewicht", entry.weightKg)
                        )
                        .foregroundStyle(theme.accent)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Datum",   entry.date),
                            y: .value("Gewicht", entry.weightKg)
                        )
                        .foregroundStyle(theme.accent)
                        .symbolSize(30)
                    }
                    .frame(height: 180)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month())
                        }
                    }
                    .chartYScale(domain: weightYDomain)
                }
            }
        }
    }

    // MARK: - Kalorien (letzte 14 Tage)

    @ViewBuilder
    private var calorieSection: some View {
        let data = last14DaysCalories
        statCard(header: "Kalorien – letzte 14 Tage") {
            if data.allSatisfy({ $0.kcal == 0 }) {
                emptyHint(
                    icon: "fork.knife",
                    text: "Sobald du Lebensmittel loggst, erscheint hier dein Kalorienverlauf."
                )
            } else {
                Chart(data, id: \.date) { day in
                    BarMark(
                        x: .value("Tag",      day.date, unit: .day),
                        y: .value("Kalorien", day.kcal)
                    )
                    .foregroundStyle(day.kcal > Double(calorieTarget) ? Color.red.opacity(0.7) : theme.accent.opacity(0.7))
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) {
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .overlay(alignment: .top) {
                    // Ziel-Linie
                    GeometryReader { geo in
                        let maxKcal = max(Double(calorieTarget) * 1.3,
                                         data.map(\.kcal).max() ?? Double(calorieTarget))
                        let yFraction = 1.0 - Double(calorieTarget) / maxKcal
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.orange.opacity(0.7))
                            .offset(y: geo.size.height * yFraction)
                    }
                }

                HStack {
                    Circle().fill(theme.accent.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Im Ziel")
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 10, height: 10).padding(.leading, 8)
                    Text("Über Ziel")
                    Spacer()
                    Circle().fill(Color.orange.opacity(0.7)).frame(width: 10, height: 10).padding(.leading, 8)
                    Text("Ziel")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - TDEE-Info

    private func tdeeSection(_ p: UserProfile) -> some View {
        statCard(header: "Profil & Ziele") {
            VStack(spacing: 0) {
                statRow("Kalorienziel", value: "\(p.currentCalorieTarget) kcal / Tag", valueColor: theme.accent)
                Divider()
                statRow("Ziel", value: p.goal.rawValue)
                Divider()
                statRow("Aktivität", value: p.activityLevel.rawValue)
                if let latest = weightEntries.first {
                    let age  = TDEECalculator.age(from: p.birthDate)
                    let tdee = TDEECalculator.tdee(
                        sex: p.sex, weightKg: latest.weightKg,
                        heightCm: p.heightCm, ageYears: age,
                        activity: p.activityLevel
                    )
                    Divider()
                    statRow("TDEE (aktuell)", value: "\(Int(tdee.rounded())) kcal")
                }
            }
        }
    }

    // MARK: - Adaptives Kalorienziel

    @ViewBuilder
    private func adaptiveSection(_ p: UserProfile) -> some View {
        let status = AdaptiveCalorieEngine.evaluate(
            weightEntries: Array(weightEntries),
            profile: p
        )

        statCard(
            header: "Adaptives Kalorienziel",
            footer: "Basiert auf der Gewichtsentwicklung der letzten 14 Tage (mind. 4 Einträge in beiden Wochenhälften)."
        ) {
            switch status {
            case .insufficientData(let have, let need):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Noch zu wenig Gewichtsdaten", systemImage: "scalemass")
                        .font(.subheadline.weight(.medium))
                    Text("\(have) von mindestens \(need) Einträgen in den letzten 14 Tagen vorhanden. Trage dein Gewicht regelmäßig ein, damit der Algorithmus greifen kann.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .onTrack(let rate):
                Label(
                    String(format: "Gut auf Kurs · %+.2f kg / Woche", rate),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(theme.accent)

            case .recommendation(let result):
                VStack(spacing: 0) {
                    rateRow("Aktuelle Rate",
                            value: String(format: "%+.2f kg / Wo.", result.actualRatePerWeek),
                            color: .primary)
                    Divider()
                    rateRow("Zielrate",
                            value: String(format: "%+.2f kg / Wo.", result.targetRatePerWeek),
                            color: .secondary)
                    Divider()
                    rateRow("Anpassung",
                            value: String(format: "%+d kcal", result.adjustmentKcal),
                            color: result.adjustmentKcal < 0 ? Color.red : theme.accent)
                    Divider()
                    rateRow("Neues Ziel",
                            value: "\(result.newTarget) kcal / Tag",
                            color: theme.accent)
                }
            }
        }

        // Anpassen-Button — nur wenn Empfehlung vorhanden
        if case .recommendation(let result) = status {
            Button {
                p.currentCalorieTarget = result.newTarget
                try? modelContext.save()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kalorienziel anpassen")
                            .font(.headline)
                        Text("\(p.currentCalorieTarget) → \(result.newTarget) kcal / Tag")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func rateRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }

    // MARK: - Körpermaße

    // Farben für Körpermaße-Charts
    private var measurementAccent: Color { theme.bodyMeasurement }
    private let measurementColors: [Color] = [
        Color(hue: 0.75, saturation: 0.82, brightness: 0.58), // lila
        Color(hue: 0.60, saturation: 0.88, brightness: 0.62), // blau
        Color(hue: 0.08, saturation: 0.92, brightness: 0.68), // orange
        Color(hue: 0.37, saturation: 0.82, brightness: 0.50), // grün
        Color(hue: 0.01, saturation: 0.85, brightness: 0.64), // rot
        Color(hue: 0.50, saturation: 0.82, brightness: 0.54), // teal
        Color(hue: 0.91, saturation: 0.72, brightness: 0.64), // pink
    ]

    // Flat data point for combined chart — lets us pre-compute outside @ChartContentBuilder
    private struct MeasurementPoint: Identifiable {
        let id = UUID()
        let seriesName: String
        let colorIndex: Int
        let date: Date
        let value: Double
        let unit: String
    }

    // Typen nach Gruppenname geordnet: [(gruppenname, typen)]
    private func groupedMeasurementTypes() -> [(name: String, types: [BodyMeasurementType])] {
        let withGroup = measurementTypes.filter { $0.groupName != nil && !($0.groupName?.isEmpty ?? true) }
        let grouped   = Dictionary(grouping: withGroup) { $0.groupName! }
        return grouped.keys.sorted().map { name in (name: name, types: grouped[name] ?? []) }
    }

    private func combinedChartPoints(cutoff: Date, types: [BodyMeasurementType]) -> [MeasurementPoint] {
        types.enumerated().flatMap { idx, type in
            allBodyMeasurements
                .filter { $0.type?.persistentModelID == type.persistentModelID && $0.date >= cutoff }
                .sorted { $0.date < $1.date }
                .map { m in MeasurementPoint(seriesName: type.name, colorIndex: idx, date: m.date, value: m.value, unit: type.unit) }
        }
    }

    @ViewBuilder
    private var bodyMeasurementsSection: some View {
        // Header mit Ansicht-Picker + Buttons
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Körpermaße")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                Spacer()
                Button {
                    measurementLogRequest = MeasurementLogRequest(initialType: nil)
                } label: {
                    Image(systemName: "ruler.fill")
                        .foregroundStyle(measurementAccent)
                }
                Button {
                    newMeasurementName = ""
                    newMeasurementUnit = ""
                    showAddMeasurementType = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(measurementAccent)
                }
            }

            if measurementTypes.isEmpty {
                // Leer-Zustand
                VStack(spacing: 12) {
                    ContentUnavailableView {
                        Label("Noch keine Maße angelegt", systemImage: "ruler")
                    } description: {
                        Text("Tippe auf + um ein Maß hinzuzufügen (z. B. Taille, Bizeps).")
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Ansicht-Modus wählen
                Picker("Ansicht", selection: $measurementDisplayMode) {
                    Text("Separat").tag("separate")
                    Text("Kombiniert").tag("combined")
                }
                .pickerStyle(.segmented)

                if measurementDisplayMode == "combined" {
                    combinedMeasurementCard
                } else {
                    ForEach(measurementTypes) { type in
                        separateMeasurementCard(for: type)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteMeasurementType(type)
                                } label: {
                                    Label("Maß löschen", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    // Einzelne Karte pro Maßtyp
    private func separateMeasurementCard(for type: BodyMeasurementType) -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let data   = allBodyMeasurements
            .filter { $0.type?.persistentModelID == type.persistentModelID && $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        return statCard(header: type.name) {
            if data.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch keine Einträge")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        measurementLogRequest = MeasurementLogRequest(initialType: type)
                    } label: {
                        Label("Jetzt messen", systemImage: "ruler.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(measurementAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                if let last = data.last {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aktuell").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.1f \(type.unit)", last.value))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(measurementAccent)
                        }
                        Spacer()
                        if data.count >= 2 {
                            let delta = last.value - data[data.count - 2].value
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("vs. letztes Mal").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%+.1f \(type.unit)", delta))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(delta == 0 ? Color.secondary : (delta > 0 ? Color.orange : theme.accent))
                            }
                        }
                    }
                    .padding(.bottom, 10)

                    if data.count >= 2 {
                        Chart {
                            ForEach(data) { m in
                                LineMark(
                                    x: .value("Datum", m.date),
                                    y: .value(type.unit, m.value)
                                )
                                .foregroundStyle(measurementAccent)
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Datum", m.date),
                                    y: .value(type.unit, m.value)
                                )
                                .foregroundStyle(measurementAccent)
                                .symbolSize(25)
                            }
                        }
                        .frame(height: 130)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) {
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }

                Button {
                    measurementLogRequest = MeasurementLogRequest(initialType: type)
                } label: {
                    Label("Neue Messung", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(measurementAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    // Kombinierte Ansicht: eine Karte pro Gruppe + "Gruppen verwalten"-Button
    @ViewBuilder
    private var combinedMeasurementCard: some View {
        let cutoff   = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let groups   = groupedMeasurementTypes()

        // Button "Gruppen verwalten"
        Button {
            showGroupManager = true
        } label: {
            Label("Gruppen verwalten", systemImage: "folder.badge.gear")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(measurementAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(measurementAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)

        if groups.isEmpty {
            // Noch keine Gruppen → alle in einem Chart + Hinweis
            groupChartCard(header: "Alle Maße – 90 Tage", types: measurementTypes, cutoff: cutoff)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Erstelle Gruppen um Maße getrennt darzustellen.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        } else {
            // Eine Karte pro Gruppe
            ForEach(groups, id: \.name) { group in
                groupChartCard(header: group.name, types: group.types, cutoff: cutoff)
            }
            // Alle Maße zusammen
            groupChartCard(header: "Alle Maße", types: measurementTypes, cutoff: cutoff)
        }
    }

    // Chart-Karte für eine Gruppe von Maßtypen
    private func groupChartCard(header: String, types: [BodyMeasurementType], cutoff: Date) -> some View {
        let chartPoints = combinedChartPoints(cutoff: cutoff, types: types)

        return statCard(header: header) {
            if chartPoints.isEmpty {
                Text("Noch keine Messungen eingetragen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Datum", point.date),
                            y: .value(point.unit, point.value),
                            series: .value("Maß", point.seriesName)
                        )
                        .foregroundStyle(measurementColors[point.colorIndex % measurementColors.count])
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Datum", point.date),
                            y: .value(point.unit, point.value)
                        )
                        .foregroundStyle(measurementColors[point.colorIndex % measurementColors.count])
                        .symbolSize(20)
                    }
                }
                .frame(height: types.count > 1 ? 180 : 130)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .padding(.bottom, types.count > 1 ? 8 : 4)

                // Legende (nur wenn mehrere Typen)
                if types.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(types.indices, id: \.self) { i in
                            let t = types[i]
                            let lastVal = allBodyMeasurements
                                .filter { $0.type?.persistentModelID == t.persistentModelID }
                                .sorted { $0.date < $1.date }.last
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(measurementColors[i % measurementColors.count])
                                    .frame(width: 8, height: 8)
                                Text(t.name).font(.caption)
                                Spacer()
                                if let v = lastVal {
                                    Text(String(format: "%.1f \(t.unit)", v.value))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(measurementColors[i % measurementColors.count])
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }

            Button {
                measurementLogRequest = MeasurementLogRequest(initialType: types.first)
            } label: {
                Label("Neue Messung", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(measurementAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, types.count > 1 ? 4 : 8)
        }
    }

    // MARK: - Hilfsmethoden

    private func deleteMeasurementType(_ type: BodyMeasurementType) {
        modelContext.delete(type)
        try? modelContext.save()
    }

    private func emptyHint(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var weightChartData: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        return weightEntries
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    private var weightYDomain: ClosedRange<Double> {
        let values = weightChartData.map { $0.weightKg }
        let min = (values.min() ?? 60) - 2
        let max = (values.max() ?? 80) + 2
        return min...max
    }

    // MARK: - Gewichtsprognose

    private struct WeightPredictionData {
        let targetKg:    Double
        let currentKg:   Double
        let diff:        Double   // Δ zum Ziel (negativ = abnehmen)
        let weeklyRate:  Double   // kg / Woche (negativ = abnehmen)
        let weeksNeeded: Double
        let targetDate:  Date
    }

    private var weightPrediction: WeightPredictionData? {
        guard let target = profile?.targetWeightKg else { return nil }
        let sorted = weightChartData
        guard sorted.count >= 4,
              let first = sorted.first, let last = sorted.last else { return nil }
        let daySpan = last.date.timeIntervalSince(first.date) / 86400
        guard daySpan >= 14 else { return nil }

        let weeklyRate = (last.weightKg - first.weightKg) / daySpan * 7
        let diff = target - last.weightKg

        // Prognose nur sinnvoll wenn Rate und Richtung übereinstimmen
        guard weeklyRate != 0.0, (diff < 0) == (weeklyRate < 0) else { return nil }
        let weeksNeeded = diff / weeklyRate
        guard weeksNeeded > 0 && weeksNeeded < 520 else { return nil }

        let targetDate = Calendar.current.date(
            byAdding: .day,
            value: Int((weeksNeeded * 7).rounded()),
            to: last.date
        ) ?? last.date

        return WeightPredictionData(
            targetKg:    target,
            currentKg:   last.weightKg,
            diff:        diff,
            weeklyRate:  weeklyRate,
            weeksNeeded: weeksNeeded,
            targetDate:  targetDate
        )
    }

    @ViewBuilder
    private var weightPredictionSection: some View {
        if let pred = weightPrediction {
            statCard(
                header: "Gewichtsprognose",
                footer: "Basiert auf dem Gewichtsverlauf der letzten 90 Tage (mind. 4 Einträge über ≥ 14 Tage)."
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zielgewicht")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f kg", pred.targetKg))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Voraussichtlich erreicht")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(pred.targetDate, format: .dateTime.day().month(.wide).year())
                            .font(.headline).foregroundStyle(theme.accent)
                    }
                }
                .padding(.bottom, 10)

                Divider()

                HStack {
                    Label(String(format: "%.1f kg verbleibend", abs(pred.diff)),
                          systemImage: "arrow.right.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "~%.0f Wochen", pred.weeksNeeded))
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .padding(.vertical, 6)

                Text(String(format: "Trend: %+.2f kg / Woche", pred.weeklyRate))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var last14DaysCalories: [(date: Date, kcal: Double)] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<14).reversed().compactMap { daysAgo -> (date: Date, kcal: Double)? in
            guard let day  = cal.date(byAdding: .day, value: -daysAgo, to: today),
                  let next = cal.date(byAdding: .day, value:  1,       to: day)
            else { return nil }
            let sum = diaryEntries
                .filter { $0.date >= day && $0.date < next }
                .reduce(0) { $0 + $1.kcal }
            return (date: day, kcal: sum)
        }
    }
}

// MARK: - WeightLoggerSheet

struct WeightLoggerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    @State private var weightKg: Double = 75
    @State private var date: Date       = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Gewicht") {
                    NumericStepperView(value: $weightKg, range: 30...300, step: 0.1, unit: "kg")
                }

                Section("Datum") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                if !entries.isEmpty {
                    Section("Letzte Einträge") {
                        ForEach(entries.prefix(5)) { entry in
                            HStack {
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f kg", entry.weightKg))
                                    .fontWeight(.medium)
                            }
                        }
                        .onDelete { offsets in
                            let toDelete = Array(entries.prefix(5))
                            for i in offsets { modelContext.delete(toDelete[i]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Gewicht eintragen")
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
        .onAppear {
            if let last = entries.first { weightKg = last.weightKg }
        }
    }

    private func save() {
        let entry = WeightEntry(date: date, weightKg: weightKg)
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - BodyMeasurementLoggerSheet

struct BodyMeasurementLoggerSheet: View {
    let types: [BodyMeasurementType]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var selectedType: BodyMeasurementType?
    @State private var value:  Double = 0
    @State private var date:   Date   = .now

    // initialType direkt in @State schreiben — sicherer als .onAppear
    init(types: [BodyMeasurementType], initialType: BodyMeasurementType? = nil) {
        self.types = types
        _selectedType = State(initialValue: initialType ?? types.first)
    }

    private var canSave: Bool { selectedType != nil && value > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Maß") {
                    Picker("Maß wählen", selection: $selectedType) {
                        Text("Bitte wählen").tag(Optional<BodyMeasurementType>.none)
                        ForEach(types) { t in
                            Text("\(t.name) (\(t.unit))").tag(Optional(t))
                        }
                    }
                }

                Section("Wert") {
                    HStack {
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                        if let t = selectedType {
                            Text(t.unit).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Datum") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .navigationTitle("Messung eintragen")
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
        }
    }

    private func save() {
        guard let t = selectedType else { return }
        let m = BodyMeasurement(type: t, value: value, date: date)
        modelContext.insert(m)
        try? modelContext.save()
        dismiss()
    }
}

// Wrapper damit sheet(item:) bei jedem Öffnen eine frische View erzeugt
struct MeasurementLogRequest: Identifiable {
    let id = UUID()
    var initialType: BodyMeasurementType?
}

// MARK: - GroupManagerSheet

struct GroupManagerSheet: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurementType.sortOrder) private var measurementTypes: [BodyMeasurementType]

    @State private var newGroupName = ""

    // Alle bekannten Gruppenbezeichnungen aus den Maßen
    private var allGroups: [String] {
        Array(Set(measurementTypes.compactMap { $0.groupName }.filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                // Neue Gruppe anlegen
                Section {
                    HStack {
                        TextField("z. B. Oberkörper", text: $newGroupName)
                        Button("Anlegen") {
                            let name = newGroupName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty, !allGroups.contains(name) else { return }
                            // Gruppe merken, indem wir nichts weiter tun — sie erscheint
                            // sobald ein Maß zugeordnet wird. Hier trotzdem leeren.
                            newGroupName = ""
                        }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Neue Gruppe")
                } footer: {
                    Text("Tippe einen Namen ein und ordne dann unten Maße dieser Gruppe zu.")
                }

                // Maße den Gruppen zuordnen
                if !measurementTypes.isEmpty {
                    Section("Maße zuordnen") {
                        ForEach(measurementTypes) { type in
                            TypeGroupRow(
                                type: type,
                                availableGroups: allGroups,
                                pendingNewGroup: newGroupName.trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }
                }

                // Übersicht bestehender Gruppen mit Löschen-Option
                if !allGroups.isEmpty {
                    Section("Bestehende Gruppen") {
                        ForEach(allGroups, id: \.self) { group in
                            let count = measurementTypes.filter { $0.groupName == group }.count
                            HStack {
                                Label(group, systemImage: "folder.fill")
                                    .foregroundStyle(Color(hue: 0.75, saturation: 0.82, brightness: 0.58))
                                Spacer()
                                Text("\(count) Maß\(count == 1 ? "" : "e")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteGroup(group)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gruppen verwalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func deleteGroup(_ group: String) {
        for type in measurementTypes where type.groupName == group {
            type.groupName = nil
        }
        try? modelContext.save()
    }
}

// Zeile für ein einzelnes Maß mit Gruppen-Picker
private struct TypeGroupRow: View {
    let type: BodyMeasurementType
    let availableGroups: [String]
    let pendingNewGroup: String   // Vorschau: noch nicht gespeicherte neue Gruppe

    // Alle wählbaren Gruppen inkl. aktuell getippter (falls noch nicht vorhanden)
    private var groups: [String] {
        var g = availableGroups
        if !pendingNewGroup.isEmpty && !g.contains(pendingNewGroup) {
            g.append(pendingNewGroup)
        }
        return g.sorted()
    }

    var body: some View {
        HStack {
            Text(type.name)
            Spacer()
            Picker("", selection: Binding(
                get: { type.groupName ?? "" },
                set: { type.groupName = $0.isEmpty ? nil : $0 }
            )) {
                Text("Keine Gruppe").tag("")
                ForEach(groups, id: \.self) { group in
                    Text(group).tag(group)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color(hue: 0.75, saturation: 0.82, brightness: 0.58))
        }
    }
}
