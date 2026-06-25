import SwiftUI
import SwiftData

// MARK: - Haupt-View

struct OnboardingView: View {
    @Environment(AppTheme.self)  private var theme
    @Environment(\.modelContext) private var modelContext
    @State private var step = 0

    // Eingabewerte
    @State private var sex: Sex = .male
    @State private var birthDate: Date = Calendar.current.date(
        byAdding: .year, value: -25, to: Date()
    ) ?? Date()
    @State private var heightCm: Double = 175
    @State private var weightKg: Double = 75
    @State private var activityLevel: ActivityLevel = .moderatelyActive
    @State private var goal: Goal = .maintain
    @State private var weeklyRateKg: Double = 0.5

    private let totalSteps = 8   // Schritte 0 … 7

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Fortschrittsbalken (ab Schritt 1)
                if step > 0 {
                    ProgressView(value: Double(step), total: Double(totalSteps - 1))
                        .tint(theme.accent)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                Spacer()

                // Schrittinhalt
                stepContent
                    .id(step)           // erzwingt View-Neubau → Transition greift
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))

                Spacer()

                // Navigationsleiste
                navigationBar
                    .padding(24)
            }
        }
    }

    // MARK: - Schrittauswahl

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: sexStep
        case 2: birthDateStep
        case 3: heightStep
        case 4: weightStep
        case 5: activityStep
        case 6: goalStep
        case 7: summaryStep
        default: EmptyView()
        }
    }

    // MARK: - Navigationsleiste

    private var navigationBar: some View {
        HStack {
            if step > 0 {
                Button {
                    HapticManager.impact(.light)
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Label("Zurück", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if step < totalSteps - 1 {
                Button {
                    HapticManager.impact(.medium)
                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                } label: {
                    Text("Weiter")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            } else {
                Button {
                    HapticManager.notification(.success)
                    saveProfile()
                } label: {
                    Text("Los geht's!")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
    }

    // MARK: - Schritt 0: Willkommen

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(theme.accent)

            VStack(spacing: 10) {
                Text("Willkommen bei Calo")
                    .font(.largeTitle.bold())

                Text("Beantworte ein paar kurze Fragen,\ndamit wir dein Kalorienziel berechnen können.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }

    // MARK: - Schritt 1: Geschlecht

    private var sexStep: some View {
        VStack(spacing: 36) {
            stepHeader("Biologisches Geschlecht",
                       subtitle: "Wird für die BMR-Berechnung benötigt")

            HStack(spacing: 16) {
                ForEach(Sex.allCases, id: \.self) { s in
                    sexCard(s)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func sexCard(_ s: Sex) -> some View {
        let selected = sex == s
        return Button {
            HapticManager.selection()
            sex = s
        } label: {
            VStack(spacing: 14) {
                Image(systemName: s == .male ? "figure.stand" : "figure.stand.dress")
                    .font(.system(size: 52))
                Text(s.rawValue)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(selected ? theme.accent.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(selected ? theme.accent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schritt 2: Geburtsdatum

    private var birthDateStep: some View {
        VStack(spacing: 36) {
            stepHeader("Geburtsdatum",
                       subtitle: "Dein Alter beeinflusst den Kalorienbedarf")

            DatePicker("Geburtsdatum", selection: $birthDate,
                       in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Schritt 3: Größe

    private var heightStep: some View {
        VStack(spacing: 36) {
            stepHeader("Körpergröße", subtitle: "In Zentimetern")
            NumericStepperView(value: $heightCm, range: 120...240, step: 1, unit: "cm")
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Schritt 4: Gewicht

    private var weightStep: some View {
        VStack(spacing: 36) {
            stepHeader("Aktuelles Gewicht", subtitle: "In Kilogramm")
            NumericStepperView(value: $weightKg, range: 30...250, step: 0.5, unit: "kg")
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Schritt 5: Aktivitätslevel

    private var activityStep: some View {
        VStack(spacing: 24) {
            stepHeader("Aktivitätslevel", subtitle: "Wie aktiv bist du im Alltag?")

            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    activityRow(level)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func activityRow(_ level: ActivityLevel) -> some View {
        let selected = activityLevel == level
        return Button {
            HapticManager.selection()
            activityLevel = level
        } label: {
            HStack {
                Text(level.rawValue)
                    .font(.headline)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding()
            .background(selected ? theme.accent.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schritt 6: Ziel + Rate

    private var goalStep: some View {
        VStack(spacing: 24) {
            stepHeader("Dein Ziel", subtitle: "Was möchtest du erreichen?")

            VStack(spacing: 10) {
                ForEach(Goal.allCases, id: \.self) { g in
                    goalRow(g)
                }

                if goal != .maintain {
                    rateSlider
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func goalRow(_ g: Goal) -> some View {
        let selected = goal == g
        return Button {
            HapticManager.selection()
            withAnimation { goal = g }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.rawValue).font(.headline)
                    Text(goalSubtitle(g)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                }
            }
            .padding()
            .background(selected ? theme.accent.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var rateSlider: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zielrate: \(String(format: "%.1f", weeklyRateKg)) kg / Woche")
                .font(.subheadline.weight(.medium))
            Slider(value: $weeklyRateKg, in: 0.1...1.0, step: 0.1)
                .tint(theme.accent)
            HStack {
                Text("0,1 kg").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("1,0 kg").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Schritt 7: Zusammenfassung

    private var summaryStep: some View {
        let ageYears  = TDEECalculator.age(from: birthDate)
        let tdeeValue = TDEECalculator.tdee(
            sex: sex, weightKg: weightKg, heightCm: heightCm,
            ageYears: ageYears, activity: activityLevel
        )
        let target = TDEECalculator.calorieTarget(
            tdee: tdeeValue, goal: goal,
            weeklyRateKg: goal == .maintain ? 0 : weeklyRateKg
        )

        return VStack(spacing: 28) {
            stepHeader("Dein Kalorienziel", subtitle: "Basierend auf deinen Angaben")

            VStack(spacing: 4) {
                Text("\(target)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                Text("kcal / Tag")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                summaryRow("TDEE (Gesamtbedarf)", value: "\(Int(tdeeValue.rounded())) kcal")
                Divider().padding(.leading)
                summaryRow("Ziel", value: goal.rawValue)
                if goal != .maintain {
                    Divider().padding(.leading)
                    summaryRow("Rate", value: "\(String(format: "%.1f", weeklyRateKg)) kg/Woche")
                }
                Divider().padding(.leading)
                summaryRow("Alter", value: "\(ageYears) Jahre")
                Divider().padding(.leading)
                summaryRow("Größe", value: "\(Int(heightCm)) cm")
                Divider().padding(.leading)
                summaryRow("Gewicht", value: "\(String(format: "%.1f", weightKg)) kg")
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Hilfsviews

    private func stepHeader(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func goalSubtitle(_ g: Goal) -> String {
        switch g {
        case .lose:     "Kaloriendefizit — Gewicht abnehmen"
        case .maintain: "Kalorienziel = TDEE"
        case .gain:     "Kalorienüberschuss — Muskeln aufbauen"
        }
    }

    // MARK: - Profil speichern

    private func saveProfile() {
        let ageYears  = TDEECalculator.age(from: birthDate)
        let tdeeValue = TDEECalculator.tdee(
            sex: sex, weightKg: weightKg, heightCm: heightCm,
            ageYears: ageYears, activity: activityLevel
        )
        let target = TDEECalculator.calorieTarget(
            tdee: tdeeValue, goal: goal,
            weeklyRateKg: goal == .maintain ? 0 : weeklyRateKg
        )

        let profile = UserProfile(
            sex: sex,
            birthDate: birthDate,
            heightCm: heightCm,
            activityLevel: activityLevel,
            goal: goal,
            weeklyRateKg: goal == .maintain ? 0 : weeklyRateKg,
            currentCalorieTarget: target
        )
        modelContext.insert(profile)

        // Erstes Gewichtseintrag anlegen
        modelContext.insert(WeightEntry(weightKg: weightKg))

        try? modelContext.save()
    }
}

// MARK: - NumericStepperView

/// Zeigt einen großen Zahlenwert mit Stepper-Kontrolle.
struct NumericStepperView: View {
    @Environment(AppTheme.self) private var theme

    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedValue)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                Text(unit)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accent.opacity(0.7))
            }

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .scaleEffect(1.2)
                .onChange(of: value) { HapticManager.selection() }
        }
    }

    private var formattedValue: String {
        step >= 1 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
