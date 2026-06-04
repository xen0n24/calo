import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProfileView: View {
    @Query private var profiles:      [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Environment(\.modelContext) private var modelContext

    @Environment(AppTheme.self) private var theme

    @State private var showResetConfirmation = false
    @State private var showEdit              = false

    // Benachrichtigungs-Einstellungen (AppStorage = kein SwiftData nötig)
    @AppStorage("notif.logging.enabled") private var loggingEnabled  = false
    @AppStorage("notif.logging.hour")    private var loggingHour     = 12
    @AppStorage("notif.logging.minute")  private var loggingMinute   = 0
    @AppStorage("notif.weighin.enabled") private var weighInEnabled  = false
    @AppStorage("notif.weighin.weekday") private var weighInWeekday  = 2   // Montag
    @AppStorage("notif.weighin.hour")    private var weighInHour     = 8
    @AppStorage("notif.weighin.minute")  private var weighInMinute   = 0
    @AppStorage("feature.bodyMeasurements") private var bodyMeasurementsEnabled = false

    private var profile: UserProfile? { profiles.first }

    @Query(sort: \MealTemplate.createdAt, order: .reverse) private var templates: [MealTemplate]

    @State private var showTemplateEditor        = false
    @State private var editingTemplate: MealTemplate? = nil

    // Backup & Restore
    @State private var shareURL:    ShareURL?  = nil
    @State private var showImporter             = false
    @State private var isExporting              = false
    @State private var importResult: String?   = nil

    var body: some View {
        NavigationStack {
            if let p = profile {
                List {
                    // MARK: Körperdaten
                    Section("Körperdaten") {
                        LabeledContent("Geschlecht",   value: p.sex.rawValue)
                        LabeledContent("Geburtsdatum", value: formattedBirthDate(p.birthDate))
                        LabeledContent("Alter",        value: "\(TDEECalculator.age(from: p.birthDate)) Jahre")
                        LabeledContent("Größe",        value: "\(Int(p.heightCm)) cm")
                        if let w = weightEntries.first?.weightKg {
                            let bmi = w / pow(p.heightCm / 100.0, 2)
                            BMIScaleRow(bmi: bmi)
                                .padding(.vertical, 4)
                        }
                    }

                    // MARK: Aktivität & Ziele
                    Section("Aktivität & Ziele") {
                        LabeledContent("Aktivitätslevel", value: p.activityLevel.rawValue)
                        LabeledContent("Ziel",            value: p.goal.rawValue)
                        if p.goal != .maintain {
                            LabeledContent("Zielrate", value: "\(String(format: "%.1f", p.weeklyRateKg)) kg / Woche")
                        }
                    }

                    // MARK: Kalorienziel
                    Section {
                        VStack(spacing: 6) {
                            Text("\(p.currentCalorieTarget)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent)
                            Text("kcal / Tag")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    } header: { Text("Tägliches Kalorienziel") }

                    // MARK: TDEE-Info
                    Section {
                        LabeledContent("TDEE (Gesamtbedarf)", value: tdeeString(for: p))
                    } header: {
                        Text("Berechnung")
                    } footer: {
                        Text("TDEE = Grundumsatz × Aktivitätsfaktor (Mifflin-St-Jeor)")
                    }

                    // MARK: Erinnerungen
                    Section {
                        // Tägliche Logging-Erinnerung
                        Toggle("Tägliche Logging-Erinnerung", isOn: $loggingEnabled)
                            .onChange(of: loggingEnabled) { _, on in
                                Task { await handleLoggingToggle(on) }
                            }
                        if loggingEnabled {
                            DatePicker(
                                "Uhrzeit",
                                selection: loggingTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        Divider()

                        // Gewichts-Erinnerung
                        Toggle("Gewichtserinnerung (wöchentlich)", isOn: $weighInEnabled)
                            .onChange(of: weighInEnabled) { _, on in
                                Task { await handleWeighInToggle(on) }
                            }
                        if weighInEnabled {
                            Picker("Wochentag", selection: $weighInWeekday) {
                                Text("Montag").tag(2)
                                Text("Dienstag").tag(3)
                                Text("Mittwoch").tag(4)
                                Text("Donnerstag").tag(5)
                                Text("Freitag").tag(6)
                                Text("Samstag").tag(7)
                                Text("Sonntag").tag(1)
                            }
                            .onChange(of: weighInWeekday) { _, _ in rescheduleWeighIn() }
                            DatePicker(
                                "Uhrzeit",
                                selection: weighInTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                        }
                    } header: {
                        Text("Erinnerungen")
                    } footer: {
                        Text("Benötigt Benachrichtigungs-Erlaubnis. Beim ersten Aktivieren erscheint ein Systemdialog.")
                    }

                    // MARK: Vorlagen
                    Section {
                        ForEach(templates) { template in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(template.entries.count) Einträge · \(template.mealType.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { editingTemplate = template } label: {
                                    Image(systemName: "pencil.circle")
                                        .foregroundStyle(.blue.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onDelete { offsets in deleteTemplates(at: offsets) }

                        Button {
                            showTemplateEditor = true
                        } label: {
                            Label("Neue Vorlage", systemImage: "plus.circle")
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Vorlagen")
                    } footer: {
                        Text("Vorlagen können im Tagebuch per Menü bei einer Mahlzeit eingefügt werden.")
                    }

                    // MARK: Datensicherung
                    Section {
                        Button {
                            Task { await performExport() }
                        } label: {
                            Label(isExporting ? "Exportiere…" : "Backup exportieren",
                                  systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.green)
                        }
                        .disabled(isExporting)

                        Button { showImporter = true } label: {
                            Label("Backup importieren", systemImage: "square.and.arrow.down")
                                .foregroundStyle(.blue)
                        }

                        if let msg = importResult {
                            Text(msg).font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Datensicherung")
                    } footer: {
                        Text("Exportiert alle Daten als JSON-Datei. Beim Import werden nur fehlende Einträge hinzugefügt.")
                    }

                    // MARK: Design & Optionale Features
                    Section {
                        NavigationLink("Design anpassen") {
                            ThemeView()
                        }
                        NavigationLink("Optionale Features") {
                            OptionalFeaturesView()
                        }
                    }

                    // MARK: Profil zurücksetzen
                    Section {
                        Button("Profil zurücksetzen", role: .destructive) {
                            showResetConfirmation = true
                        }
                    }
                }
                .navigationTitle("Profil")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Bearbeiten") { showEdit = true }
                    }
                }
                .sheet(isPresented: $showEdit) {
                    ProfileEditSheet(profile: p)
                }
                .sheet(isPresented: $showTemplateEditor) {
                    MealTemplateEditorView()
                }
                .sheet(item: $editingTemplate) { t in
                    MealTemplateEditorView(existingTemplate: t)
                }
                .sheet(item: $shareURL) { s in ActivityView(url: s.url) }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                    if case .success(let url) = result {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        Task { await performImport(from: url) }
                    }
                }
                .confirmationDialog(
                    "Profil wirklich löschen?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Löschen", role: .destructive) { resetProfile() }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Das Onboarding wird erneut gestartet. Alle anderen Daten bleiben erhalten.")
                }
            }
        }
    }

    // MARK: - BMI

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5:  return "Untergewicht"
        case ..<25.0:  return "Normalgewicht"
        case ..<30.0:  return "Übergewicht"
        default:       return "Adipositas"
        }
    }

    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5:  return .blue
        case ..<25.0:  return .green
        case ..<30.0:  return .orange
        default:       return .red
        }
    }

    // MARK: - Benachrichtigungen

    private var loggingTimeBinding: Binding<Date> {
        Binding(
            get: { makeDate(hour: loggingHour, minute: loggingMinute) },
            set: { d in
                loggingHour   = Calendar.current.component(.hour,   from: d)
                loggingMinute = Calendar.current.component(.minute, from: d)
                if loggingEnabled {
                    NotificationManager.scheduleDailyLogging(hour: loggingHour, minute: loggingMinute)
                }
            }
        )
    }

    private var weighInTimeBinding: Binding<Date> {
        Binding(
            get: { makeDate(hour: weighInHour, minute: weighInMinute) },
            set: { d in
                weighInHour   = Calendar.current.component(.hour,   from: d)
                weighInMinute = Calendar.current.component(.minute, from: d)
                rescheduleWeighIn()
            }
        )
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? .now
    }

    private func handleLoggingToggle(_ on: Bool) async {
        if on {
            let granted = await NotificationManager.requestAuthorization()
            if granted {
                NotificationManager.scheduleDailyLogging(hour: loggingHour, minute: loggingMinute)
            } else {
                loggingEnabled = false
            }
        } else {
            NotificationManager.cancelDailyLogging()
        }
    }

    private func handleWeighInToggle(_ on: Bool) async {
        if on {
            let granted = await NotificationManager.requestAuthorization()
            if granted {
                NotificationManager.scheduleWeighIn(weekday: weighInWeekday, hour: weighInHour, minute: weighInMinute)
            } else {
                weighInEnabled = false
            }
        } else {
            NotificationManager.cancelWeighIn()
        }
    }

    private func rescheduleWeighIn() {
        guard weighInEnabled else { return }
        NotificationManager.scheduleWeighIn(weekday: weighInWeekday, hour: weighInHour, minute: weighInMinute)
    }

    // MARK: - TDEE

    private func tdeeString(for p: UserProfile) -> String {
        let age      = TDEECalculator.age(from: p.birthDate)
        let weightKg = weightEntries.first?.weightKg ?? Double(p.heightCm - 100)
        let tdee = TDEECalculator.tdee(
            sex: p.sex, weightKg: weightKg,
            heightCm: p.heightCm, ageYears: age,
            activity: p.activityLevel
        )
        return "\(Int(tdee.rounded())) kcal"
    }

    private func formattedBirthDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    private func resetProfile() {
        for p in profiles { modelContext.delete(p) }
        try? modelContext.save()
    }

    // MARK: - Backup & Restore

    private func performExport() async {
        isExporting = true
        if let url = try? BackupManager.export(context: modelContext) {
            shareURL = ShareURL(url: url)
        }
        isExporting = false
    }

    private func performImport(from url: URL) async {
        if let r = try? BackupManager.importBackup(from: url, context: modelContext) {
            importResult = r.summary
        } else {
            importResult = "Import fehlgeschlagen."
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(templates[i]) }
        try? modelContext.save()
    }

}

// MARK: - BMIScaleRow

private struct BMIScaleRow: View {
    let bmi: Double

    private let minBMI = 15.0
    private let maxBMI = 40.0

    private func frac(_ v: Double) -> Double {
        Swift.max(0, Swift.min(1, (v - minBMI) / (maxBMI - minBMI)))
    }

    private var markerColor: Color {
        switch bmi {
        case ..<18.5: return .blue
        case ..<25.0: return .green
        case ..<30.0: return .orange
        default:       return .red
        }
    }

    private var category: String {
        switch bmi {
        case ..<18.5: return "Untergewicht"
        case ..<25.0: return "Normalgewicht"
        case ..<30.0: return "Übergewicht"
        default:       return "Adipositas"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", bmi))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(markerColor)
                    .monospacedDigit()
                Text(category)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(markerColor)
                Spacer()
                Text("BMI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Farbsegmente
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue.opacity(0.65))
                            .frame(width: w * (3.5 / 25.0))
                        Rectangle().fill(Color.green.opacity(0.65))
                            .frame(width: w * (6.5 / 25.0))
                        Rectangle().fill(Color.orange.opacity(0.65))
                            .frame(width: w * (5.0 / 25.0))
                        Rectangle().fill(Color.red.opacity(0.65))
                            .frame(width: w * (10.0 / 25.0))
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(y: 14)

                    // Trennlinien an den Schwellenwerten
                    ForEach([18.5, 25.0, 30.0], id: \.self) { bp in
                        Rectangle()
                            .fill(Color(.systemBackground).opacity(0.7))
                            .frame(width: 1.5, height: 8)
                            .offset(x: w * frac(bp), y: 14)
                    }

                    // Pfeil-Marker an aktuellem BMI
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(markerColor)
                        .offset(x: w * frac(bmi) - 5, y: 1)
                }
            }
            .frame(height: 24)

            // Grenzwert-Labels
            HStack {
                Text("15")
                Spacer()
                Text("18.5")
                Spacer()
                Text("25")
                Spacer()
                Text("30")
                Spacer()
                Text("40")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - AddMeasurementTypeSheet

struct AddMeasurementTypeSheet: View {
    @Binding var name: String
    @Binding var unit: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !unit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z.B. Taille", text: $name)
                }
                Section("Einheit") {
                    TextField("z.B. cm", text: $unit)
                }
            }
            .navigationTitle("Neues Maß")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
