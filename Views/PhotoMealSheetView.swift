import SwiftUI
import PhotosUI
import SwiftData
import AVFoundation

// MARK: - DraftItem

struct DraftItem: Identifiable {
    let id       = UUID()
    var name:        String
    var grams:       Double
    var matchedFood: Food?
}

// MARK: - PhotoMealSheet

struct PhotoMealSheet: View {
    let date:        Date
    let initialMeal: MealType

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Query private var allFoods: [Food]

    @State private var selectedMeal:      MealType
    @State private var capturedImage:     UIImage?          = nil
    @State private var draftItems:        [DraftItem]       = []
    @State private var isAnalyzing                          = false
    @State private var errorMessage:      String?           = nil   // Fehler in comment/textInput-Phase (inline)
    @State private var confirmError:      String?           = nil   // Fehler in confirm-Phase (inline)
    @State private var retryStatus:       String?           = nil   // z. B. "Versuch 2/3…"
    @State private var photosPickerItem:  PhotosPickerItem? = nil
    @State private var showCamera                           = false
    @State private var showCameraPermissionAlert             = false
    @State private var showFoodPicker                       = false
    @State private var editingItemID:     UUID?             = nil
    @State private var pickerInitialSearch: String          = ""
    @State private var detectedLabels:    [String]          = []
    @State private var showLabels                           = false
    @State private var userComment:       String            = ""
    @State private var analysisComplete                     = false
    @State private var expandedGramsID:   UUID?            = nil
    @State private var showAdjustment                       = false
    @State private var adjustmentPrompt:  String           = ""
    @State private var showAddItem                          = false
    @State private var addItemPrompt:     String           = ""
    @State private var showTextInput                        = false
    @State private var mealDescription:   String           = ""

    // Kein .error-Phase mehr – Fehler werden inline angezeigt, Eingaben bleiben erhalten
    private enum ViewPhase { case source, textInput, comment, analyzing, confirm }
    private var phase: ViewPhase {
        if isAnalyzing          { return .analyzing }
        if analysisComplete     { return .confirm }
        if capturedImage != nil { return .comment }
        if showTextInput        { return .textInput }
        return .source
    }

    private static let maxRetries = 3

    init(date: Date, initialMeal: MealType) {
        self.date        = date
        self.initialMeal = initialMeal
        _selectedMeal    = State(initialValue: initialMeal)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .source:    sourceView
                case .textInput: textInputView
                case .comment:   commentView
                case .analyzing: analyzingView
                case .confirm:   confirmView
                }
            }
            .navigationTitle("Mahlzeit per KI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onChange(of: photosPickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item: item) }
        }
        .alert("Kamerazugriff verweigert", isPresented: $showCameraPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte erlaube den Kamerazugriff in den iOS-Einstellungen unter Datenschutz → Kamera.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(isPresented: $showCamera) { image in
                capturedImage = image
            }
        }
        .sheet(isPresented: $showFoodPicker) {
            TemplateFoodPickerSheet(initialSearch: pickerInitialSearch) { food, grams in
                onFoodPicked(food: food, grams: grams)
                pickerInitialSearch = ""
            }
        }
    }

    // MARK: - Source

    private var sourceView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Mahlzeit per KI erfassen")
                    .font(.title3.bold())
                Text("Foto, Mediathek oder Freitext")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                Button { Task { await requestCameraForPhoto() } } label: {
                    kiOptionRow(icon: "camera.fill", color: .green,
                                title: "Foto aufnehmen",
                                desc: "KI erkennt Lebensmittel & Portionen")
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)

                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    kiOptionRow(icon: "photo.stack.fill", color: .blue,
                                title: "Aus Mediathek",
                                desc: "Vorhandenes Foto analysieren")
                }

                Divider().padding(.leading, 58)

                Button { showTextInput = true } label: {
                    kiOptionRow(icon: "text.bubble.fill", color: .purple,
                                title: "Text eingeben",
                                desc: "Freitext – auch Fastfood & Markennamen")
                }
                .buttonStyle(.plain)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()
            Spacer()

            Text("KI-Schätzung: Mengen immer überprüfen!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }

    private func kiOptionRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Text Input

    private var textInputView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 8)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                // Inline-Fehlerbanner – Text bleibt erhalten
                if let msg = errorMessage {
                    inlineErrorBanner(message: msg) {
                        let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await analyzeText(description: trimmed) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Was hast du gegessen?")
                        .font(.headline)
                    Text("Beschreibe deine Mahlzeit frei – die KI erschließt Portionen, Fastfood-Standardgrößen und Markennamen.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("z. B. '6er McNuggets, Big Mac, Curry Dip und ne Cola'",
                              text: $mealDescription, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                Button {
                    guard !trimmed.isEmpty else { return }
                    Task { await analyzeText(description: trimmed) }
                } label: {
                    Label(errorMessage != nil ? "Erneut analysieren" : "Analysieren",
                          systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding()
                        .background(trimmed.isEmpty ? Color.gray : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(trimmed.isEmpty)

                Button {
                    showTextInput   = false
                    mealDescription = ""
                    errorMessage    = nil
                } label: {
                    Text("Zurück")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Comment

    private var commentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14)).clipped()
                }

                // Inline-Fehlerbanner – Foto und Kommentar bleiben erhalten
                if let msg = errorMessage {
                    inlineErrorBanner(message: msg) {
                        guard let img = capturedImage else { return }
                        Task { await analyze(image: img, comment: userComment) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung (optional)")
                        .font(.headline)
                    Text("Hilft der KI bei schwer erkennbaren Gerichten oder Portionsgrößen.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("z. B. 'Schnitzel mit Pommes, große Portion'", text: $userComment, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task { await analyze(image: capturedImage!, comment: userComment) }
                } label: {
                    Label(errorMessage != nil ? "Erneut analysieren" : "Analysieren",
                          systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    capturedImage    = nil
                    userComment      = ""
                    errorMessage     = nil
                    photosPickerItem = nil
                } label: {
                    Text("Anderes Foto wählen")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text(retryStatus ?? "Mahlzeit wird analysiert…")
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: retryStatus)
            Spacer()
        }
    }

    // MARK: - Confirm

    private var draftTotals: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        draftItems.reduce((0, 0, 0, 0)) { acc, item in
            guard let food = item.matchedFood,
                  let n = food.nutritionPer100g else { return acc }
            let f = item.grams / 100.0
            return (acc.0 + n.kcal    * f,
                    acc.1 + n.protein  * f,
                    acc.2 + n.carbs    * f,
                    acc.3 + n.fat      * f)
        }
    }

    private var confirmView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label("KI-Schätzung: Mengen immer prüfen und ggf. anpassen!", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.green)
                    .padding(10).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Inline-Fehlerbanner für Fehler aus KI-Zusatz / Neu-Analysieren
                if let msg = confirmError {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { confirmError = nil } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Nährwert-Zusammenfassung
                if !draftItems.isEmpty {
                    let t = draftTotals
                    HStack(spacing: 0) {
                        nutritionCell(value: t.kcal,    label: "kcal",  color: .green,  isFirst: true)
                        Divider().frame(height: 32)
                        nutritionCell(value: t.protein, label: "Prot.",  color: .blue)
                        Divider().frame(height: 32)
                        nutritionCell(value: t.carbs,   label: "Koh.",   color: .orange)
                        Divider().frame(height: 32)
                        nutritionCell(value: t.fat,     label: "Fett",   color: .yellow)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Von KI erkannte Lebensmittel als antippbare Chips
                if !detectedLabels.isEmpty {
                    DisclosureGroup(isExpanded: $showLabels) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Antippen um zu suchen:")
                                .font(.caption2).foregroundStyle(.tertiary)
                            FlowLayout(spacing: 6) {
                                ForEach(detectedLabels.prefix(15), id: \.self) { label in
                                    Button {
                                        pickerInitialSearch = label
                                        editingItemID       = nil
                                        showFoodPicker      = true
                                    } label: {
                                        Text(label)
                                            .font(.caption)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Label("Von KI erkannt (\(detectedLabels.count))", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).clipped()
                }

                Picker("Mahlzeit", selection: $selectedMeal) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                ForEach($draftItems) { $item in
                    draftItemRow(item: $item)
                }

                Button {
                    editingItemID  = nil
                    showFoodPicker = true
                } label: {
                    Label("Lebensmittel hinzufügen", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.green)
                }

                // KI-Anpassung & Einzelhinzufügen
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdjustment.toggle(); if showAdjustment { showAddItem = false }
                        }
                    } label: {
                        Label("Anpassen", systemImage: "arrow.clockwise")
                            .font(.caption).frame(maxWidth: .infinity).padding(8)
                            .background(showAdjustment ? Color.orange.opacity(0.15) : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(showAdjustment ? Color.orange : Color.primary)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAddItem.toggle(); if showAddItem { showAdjustment = false }
                        }
                    } label: {
                        Label("KI-Zusatz", systemImage: "sparkles")
                            .font(.caption).frame(maxWidth: .infinity).padding(8)
                            .background(showAddItem ? Color.blue.opacity(0.12) : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(showAddItem ? Color.blue : Color.primary)
                    }
                }

                if showAdjustment {
                    VStack(spacing: 8) {
                        TextField("Was stimmt nicht? (z.B. 'ohne Pommes, Portion kleiner')",
                                  text: $adjustmentPrompt, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            let text = adjustmentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            Task { await reanalyze(comment: text) }
                        } label: {
                            Label("Neu analysieren", systemImage: "sparkles")
                                .frame(maxWidth: .infinity).padding(10)
                                .background(Color.orange).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                if showAddItem {
                    VStack(spacing: 8) {
                        TextField("Was fehlt? (z.B. 'Ketchup', 'Cola 0,5l')", text: $addItemPrompt)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            let text = addItemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            Task { await addItemViaAI(description: text) }
                        } label: {
                            Label("Per KI hinzufügen", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity).padding(10)
                                .background(Color.blue).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                let saveable = draftItems.filter { $0.matchedFood != nil }
                let skipped  = draftItems.count - saveable.count
                Button { save() } label: {
                    VStack(spacing: 2) {
                        Text(saveable.isEmpty
                             ? "Keine Einträge zum Speichern"
                             : "Hinzufügen (\(saveable.count) Einträge)")
                            .font(.headline)
                        if skipped > 0 {
                            Text("\(skipped) ohne DB-Treffer werden übersprungen")
                                .font(.caption).opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(saveable.isEmpty ? Color.gray : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(saveable.isEmpty)
            }
            .padding()
        }
    }

    private func draftItemRow(item: Binding<DraftItem>) -> some View {
        let isExpanded = expandedGramsID == item.wrappedValue.id
        let matched    = item.wrappedValue.matchedFood
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: item.name)
                        .font(.subheadline)
                    if matched == nil {
                        Text("Nicht gefunden — zum Suchen tippen")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
                // Gramm-Badge: antippen öffnet Rad-Picker
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedGramsID = isExpanded ? nil : item.wrappedValue.id
                    }
                } label: {
                    Text("\(Int(item.wrappedValue.grams)) g")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    editingItemID  = item.wrappedValue.id
                    showFoodPicker = true
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                Button {
                    draftItems.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            if isExpanded {
                Divider()
                Picker("", selection: item.grams) {
                    ForEach(Self.gramsValues, id: \.self) { v in
                        Text("\(Int(v)) g").tag(v)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private static let gramsValues: [Double] = Array(stride(from: 5.0, through: 2000.0, by: 5.0))

    private func nutritionCell(value: Double, label: String, color: Color, isFirst: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value < 10 ? String(format: "%.1f", value) : "\(Int(value))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Inline Error Banner

    @ViewBuilder
    private func inlineErrorBanner(message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Verbindungsfehler")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Button(action: onRetry) {
                Label("Erneut versuchen", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Logic

    @MainActor
    private func requestCameraForPhoto() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showCamera = true }
            else { showCameraPermissionAlert = true }
        default:
            showCameraPermissionAlert = true
        }
    }

    private func onFoodPicked(food: Food, grams: Double) {
        let snapped = max(5.0, (grams / 5.0).rounded() * 5.0)
        if let id = editingItemID,
           let idx = draftItems.firstIndex(where: { $0.id == id }) {
            draftItems[idx].matchedFood = food
            draftItems[idx].name        = food.name
            draftItems[idx].grams       = snapped
        } else {
            draftItems.append(DraftItem(name: food.name, grams: snapped, matchedFood: food))
        }
        editingItemID = nil
    }

    @MainActor
    private func loadPhoto(item: PhotosPickerItem) async {
        guard let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        capturedImage = image
    }

    // Prüft ob ein Fehler einen Retry rechtfertigt
    private func isRetriable(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let e = error as? PhotoMealRecognizer.RecognizerError {
            switch e {
            case .networkError(let code, _):
                return code == 429 || code >= 500 || code == 0
            case .parseFailed, .noItemsDetected:
                return true
            default:
                return false
            }
        }
        return true // Im Zweifel: retry
    }

    @MainActor
    private func analyze(image: UIImage, comment: String = "") async {
        isAnalyzing = true; errorMessage = nil; retryStatus = nil
        for attempt in 1...Self.maxRetries {
            if attempt > 1 {
                retryStatus = "Verbindung wird hergestellt… (Versuch \(attempt)/\(Self.maxRetries))"
                try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * 2_000_000_000)
            }
            do {
                let result     = try await PhotoMealRecognizer.recognize(image: image, comment: comment)
                detectedLabels = result.detectedLabels
                var seen       = Set<PersistentIdentifier>()
                draftItems     = result.items.compactMap { item -> DraftItem? in
                    let food    = matchOrCreate(item: item)
                    guard seen.insert(food.persistentModelID).inserted else { return nil }
                    let snapped = max(5.0, (Double(item.estimatedGrams) / 5.0).rounded() * 5.0)
                    return DraftItem(name: item.name, grams: snapped, matchedFood: food)
                }
                showLabels       = draftItems.isEmpty
                analysisComplete = true
                isAnalyzing      = false
                retryStatus      = nil
                return
            } catch {
                if !isRetriable(error) || attempt == Self.maxRetries {
                    errorMessage = error.localizedDescription
                    break
                }
                // Weiter → nächster Versuch
            }
        }
        isAnalyzing = false
        retryStatus = nil
    }

    private func match(_ name: String) -> Food? {
        allFoods
            .filter { $0.source != .recipe && FoodSearch.matches(food: $0, query: name) }
            .sorted { FoodSearch.score(food: $0, query: name) > FoodSearch.score(food: $1, query: name) }
            .first
    }

    @MainActor
    private func analyzeText(description: String) async {
        isAnalyzing = true; errorMessage = nil; retryStatus = nil
        for attempt in 1...Self.maxRetries {
            if attempt > 1 {
                retryStatus = "Verbindung wird hergestellt… (Versuch \(attempt)/\(Self.maxRetries))"
                try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * 2_000_000_000)
            }
            do {
                let result     = try await PhotoMealRecognizer.recognizeFromText(description)
                detectedLabels = result.detectedLabels
                var seen       = Set<PersistentIdentifier>()
                draftItems     = result.items.compactMap { item -> DraftItem? in
                    let food    = matchOrCreate(item: item)
                    guard seen.insert(food.persistentModelID).inserted else { return nil }
                    let snapped = max(5.0, (Double(item.estimatedGrams) / 5.0).rounded() * 5.0)
                    return DraftItem(name: item.name, grams: snapped, matchedFood: food)
                }
                showLabels       = draftItems.isEmpty
                analysisComplete = true
                isAnalyzing      = false
                retryStatus      = nil
                return
            } catch {
                if !isRetriable(error) || attempt == Self.maxRetries {
                    errorMessage = error.localizedDescription
                    break
                }
            }
        }
        isAnalyzing = false
        retryStatus = nil
    }

    @MainActor
    private func reanalyze(comment: String) async {
        showAdjustment   = false
        adjustmentPrompt = ""
        draftItems       = []
        detectedLabels   = []
        analysisComplete = false
        expandedGramsID  = nil
        confirmError     = nil
        if let image = capturedImage {
            await analyze(image: image, comment: comment)
        } else {
            let combined = mealDescription + "\nAnpassung: " + comment
            await analyzeText(description: combined)
        }
    }

    @MainActor
    private func addItemViaAI(description: String) async {
        showAddItem  = false
        isAnalyzing  = true
        confirmError = nil
        retryStatus  = nil
        for attempt in 1...Self.maxRetries {
            if attempt > 1 {
                retryStatus = "Verbindung wird hergestellt… (Versuch \(attempt)/\(Self.maxRetries))"
                try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * 2_000_000_000)
            }
            do {
                let result: RecognitionResult
                if let image = capturedImage {
                    result = try await PhotoMealRecognizer.recognizeSingle(image: image, description: description)
                } else {
                    result = try await PhotoMealRecognizer.recognizeSingleFromText(
                        existingDescription: mealDescription, addition: description)
                }
                var existingIDs = Set(draftItems.compactMap { $0.matchedFood?.persistentModelID })
                for item in result.items {
                    let food    = matchOrCreate(item: item)
                    guard existingIDs.insert(food.persistentModelID).inserted else { continue }
                    let snapped = max(5.0, (Double(item.estimatedGrams) / 5.0).rounded() * 5.0)
                    draftItems.append(DraftItem(name: item.name, grams: snapped, matchedFood: food))
                }
                addItemPrompt = ""
                isAnalyzing   = false
                retryStatus   = nil
                return
            } catch {
                if !isRetriable(error) || attempt == Self.maxRetries {
                    confirmError = error.localizedDescription
                    break
                }
            }
        }
        isAnalyzing = false
        retryStatus = nil
    }

    @MainActor
    private func matchOrCreate(item: RecognizedFoodItem) -> Food {
        if let existing = match(item.name) { return existing }

        let nutrition = Nutrition(
            kcal:    max(1, item.kcalPer100g),
            protein: max(0, item.proteinPer100g),
            carbs:   max(0, item.carbsPer100g),
            fat:     max(0, item.fatPer100g)
        )
        let food = Food(
            name:              item.name,
            source:            .custom,
            nutritionPer100g:  nutrition
        )
        modelContext.insert(nutrition)
        modelContext.insert(food)
        return food
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: date)
        for item in draftItems {
            guard let food = item.matchedFood, item.grams > 0 else { continue }
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if food.source == .custom && !trimmed.isEmpty && food.name != trimmed {
                food.name = trimmed
            }
            modelContext.insert(DiaryEntry(date: day, meal: selectedMeal, food: food, grams: item.grams))
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - CameraPickerView

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker        = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.isPresented = false
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
