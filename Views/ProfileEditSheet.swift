import SwiftUI
import SwiftData

// MARK: - Makro-Voreinstellungen

private enum MacroPreset: String, CaseIterable {
    case standard    = "Standard (30 / 40 / 30)"
    case highProtein = "High Protein (35 / 35 / 30)"
    case lowCarb     = "Low Carb (35 / 20 / 45)"
    case balanced    = "Ausgewogen (25 / 50 / 25)"

    var split: MacroSplit {
        switch self {
        case .standard:    MacroSplit(proteinPercent: 30, carbsPercent: 40, fatPercent: 30)
        case .highProtein: MacroSplit(proteinPercent: 35, carbsPercent: 35, fatPercent: 30)
        case .lowCarb:     MacroSplit(proteinPercent: 35, carbsPercent: 20, fatPercent: 45)
        case .balanced:    MacroSplit(proteinPercent: 25, carbsPercent: 50, fatPercent: 25)
        }
    }

    /// Gramm-Ziele für ein gegebenes Kalorienziel
    func grams(for kcal: Int) -> (protein: Int, carbs: Int, fat: Int) {
        let k = Double(kcal)
        return (
            protein: Int((k * split.proteinPercent / 100.0 / 4.0).rounded()),
            carbs:   Int((k * split.carbsPercent   / 100.0 / 4.0).rounded()),
            fat:     Int((k * split.fatPercent      / 100.0 / 9.0).rounded())
        )
    }
}

// MARK: - ProfileEditSheet

struct ProfileEditSheet: View {
    let profile: UserProfile

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @AppStorage("feature.microNutrients") private var microNutrientsEnabled = false

    @State private var goal:             Goal
    @State private var activityLevel:    ActivityLevel
    @State private var weeklyRateKg:     Double
    @State private var calorieTarget:    Double
    @State private var waterGoal:        Double
    @State private var macroPreset:      MacroPreset
    @State private var hasTargetWeight:  Bool
    @State private var targetWeight:     Double
    // Mikronährstoff-Ziele
    @State private var hasFiberGoal:     Bool
    @State private var fiberGoal:        Double
    @State private var hasSugarGoal:     Bool
    @State private var sugarGoal:        Double
    @State private var hasSatFatGoal:    Bool
    @State private var satFatGoal:       Double
    @State private var hasSaltGoal:      Bool
    @State private var saltGoal:         Double

    init(profile: UserProfile) {
        self.profile = profile
        _goal             = State(initialValue: profile.goal)
        _activityLevel    = State(initialValue: profile.activityLevel)
        _weeklyRateKg     = State(initialValue: profile.weeklyRateKg)
        _calorieTarget    = State(initialValue: Double(profile.currentCalorieTarget))
        _waterGoal        = State(initialValue: profile.waterGoalMl)
        _hasTargetWeight  = State(initialValue: profile.targetWeightKg != nil)
        _targetWeight     = State(initialValue: profile.targetWeightKg ?? 70)
        _hasFiberGoal     = State(initialValue: profile.fiberGoalG != nil)
        _fiberGoal        = State(initialValue: profile.fiberGoalG ?? 25)
        _hasSugarGoal     = State(initialValue: profile.sugarGoalG != nil)
        _sugarGoal        = State(initialValue: profile.sugarGoalG ?? 50)
        _hasSatFatGoal    = State(initialValue: profile.saturatedFatGoalG != nil)
        _satFatGoal       = State(initialValue: profile.saturatedFatGoalG ?? 20)
        _hasSaltGoal      = State(initialValue: profile.saltGoalG != nil)
        _saltGoal         = State(initialValue: profile.saltGoalG ?? 6)

        // Aktuelle Voreinstellung ermitteln (Fallback: Standard)
        let match = MacroPreset.allCases.first {
            Int($0.split.proteinPercent) == Int(profile.currentMacroSplit.proteinPercent) &&
            Int($0.split.carbsPercent)   == Int(profile.currentMacroSplit.carbsPercent)
        }
        _macroPreset = State(initialValue: match ?? .standard)
    }

    // Berechnetes TDEE-Ziel für aktuelle Auswahl
    private var suggestedKcal: Int {
        let age  = TDEECalculator.age(from: profile.birthDate)
        let w    = weightEntries.first?.weightKg ?? profile.heightCm - 100
        let tdee = TDEECalculator.tdee(
            sex: profile.sex, weightKg: w,
            heightCm: profile.heightCm, ageYears: age,
            activity: activityLevel
        )
        return TDEECalculator.calorieTarget(tdee: tdee, goal: goal, weeklyRateKg: weeklyRateKg)
    }

    private var gramPreview: (protein: Int, carbs: Int, fat: Int) {
        macroPreset.grams(for: Int(calorieTarget.rounded()))
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Ziel
                Section("Ziel") {
                    Picker("Ziel", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    if goal != .maintain {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Wöchentliche Rate")
                                .font(.caption).foregroundStyle(.secondary)
                            NumericStepperView(
                                value: $weeklyRateKg,
                                range: 0.1...1.0,
                                step: 0.1,
                                unit: "kg / Woche"
                            )
                        }
                    }
                    Toggle("Zielgewicht", isOn: $hasTargetWeight.animation())
                    if hasTargetWeight {
                        NumericStepperView(value: $targetWeight, range: 30...300, step: 0.5, unit: "kg")
                    }
                }

                // MARK: Aktivität
                Section("Aktivitätslevel") {
                    Picker("Aktivität", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // MARK: Kalorienziel
                Section {
                    NumericStepperView(
                        value: $calorieTarget,
                        range: 1000...6000,
                        step: 50,
                        unit: "kcal / Tag"
                    )
                    Button {
                        calorieTarget = Double(suggestedKcal)
                    } label: {
                        HStack {
                            Text("Aus TDEE vorschlagen")
                            Spacer()
                            Text("\(suggestedKcal) kcal")
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Kalorienziel")
                } footer: {
                    Text("Du kannst das Ziel manuell setzen oder automatisch aus deinem TDEE + Ziel berechnen lassen.")
                }

                // MARK: Wasserziel
                Section {
                    NumericStepperView(value: $waterGoal, range: 500...5000, step: 250, unit: "ml / Tag")
                } header: {
                    Text("Tägliches Wasserziel")
                } footer: {
                    Text("Empfohlen: 2000–3000 ml / Tag.")
                }

                // MARK: Mikronährstoff-Ziele (nur wenn Feature aktiv)
                if microNutrientsEnabled {
                    Section {
                        Toggle("Ballaststoff-Ziel", isOn: $hasFiberGoal.animation())
                        if hasFiberGoal {
                            NumericStepperView(value: $fiberGoal, range: 5...100, step: 1, unit: "g / Tag")
                        }
                        Toggle("Zuckerziel (max.)", isOn: $hasSugarGoal.animation())
                        if hasSugarGoal {
                            NumericStepperView(value: $sugarGoal, range: 5...200, step: 5, unit: "g / Tag")
                        }
                        Toggle("Ges. Fettsäuren (max.)", isOn: $hasSatFatGoal.animation())
                        if hasSatFatGoal {
                            NumericStepperView(value: $satFatGoal, range: 5...100, step: 1, unit: "g / Tag")
                        }
                        Toggle("Salzlimit", isOn: $hasSaltGoal.animation())
                        if hasSaltGoal {
                            NumericStepperView(value: $saltGoal, range: 0.5...20, step: 0.5, unit: "g / Tag")
                        }
                    } header: {
                        Text("Mikronährstoff-Ziele")
                    } footer: {
                        Text("Ziele erscheinen im Tagebuch als Fortschrittsbalken. Mikronährstoffe müssen unter Optionale Features aktiviert sein.")
                    }
                }

                // MARK: Makro-Aufteilung
                Section {
                    Picker("Voreinstellung", selection: $macroPreset) {
                        ForEach(MacroPreset.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    HStack {
                        macroPreviewCell("Eiweiß",    grams: gramPreview.protein, color: .blue)
                        Spacer()
                        macroPreviewCell("Kohlenhydr.", grams: gramPreview.carbs,   color: .orange)
                        Spacer()
                        macroPreviewCell("Fett",       grams: gramPreview.fat,     color: .yellow)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Makro-Aufteilung")
                } footer: {
                    Text("Ziele in Gramm basieren auf deinem Kalorienziel und der gewählten Aufteilung.")
                }
            }
            .navigationTitle("Profil bearbeiten")
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

    // MARK: - Hilfsmethoden

    private func macroPreviewCell(_ name: String, grams: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(grams) g")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        profile.goal                 = goal
        profile.activityLevel        = activityLevel
        profile.weeklyRateKg         = weeklyRateKg
        profile.currentCalorieTarget = Int(calorieTarget.rounded())
        profile.waterGoalMl          = waterGoal
        profile.currentMacroSplit    = macroPreset.split
        profile.lastTargetUpdate     = Date()
        profile.targetWeightKg       = hasTargetWeight ? targetWeight  : nil
        profile.fiberGoalG           = hasFiberGoal   ? fiberGoal    : nil
        profile.sugarGoalG           = hasSugarGoal   ? sugarGoal    : nil
        profile.saturatedFatGoalG    = hasSatFatGoal  ? satFatGoal   : nil
        profile.saltGoalG            = hasSaltGoal    ? saltGoal      : nil
        try? modelContext.save()
        dismiss()
    }
}
