import SwiftUI
import PhotosUI
import SwiftData
import AVFoundation

// MARK: - DraftItem

struct DraftItem: Identifiable {
    let id       = UUID()
    var name:        String       // KI-Originalname
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

    @State private var selectedMeal:     MealType
    @State private var capturedImage:    UIImage?          = nil
    @State private var draftItems:       [DraftItem]       = []
    @State private var isAnalyzing                         = false
    @State private var errorMessage:     String?           = nil
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var showCamera                          = false
    @State private var showCameraPermissionAlert            = false
    @State private var showFoodPicker                      = false
    @State private var editingItemID:    UUID?             = nil
    @State private var pickerInitialSearch: String         = ""
    @State private var detectedLabels:   [String]          = []
    @State private var showLabels                          = false

    // Vision gibt englische Labels — diese Tabelle übersetzt sie für die DB-Suche
    private static let en2de: [String: String] = [
        "broccoli":"brokkoli", "chicken":"hähnchen", "beef":"rind", "pork":"schwein",
        "fish":"fisch", "salmon":"lachs", "tuna":"thunfisch", "shrimp":"garnele",
        "egg":"ei", "potato":"kartoffel", "tomato":"tomate", "carrot":"karotte",
        "cucumber":"gurke", "lettuce":"salat", "spinach":"spinat", "pasta":"nudeln",
        "spaghetti":"spaghetti", "rice":"reis", "bread":"brot", "cheese":"käse",
        "yogurt":"joghurt", "milk":"milch", "butter":"butter", "apple":"apfel",
        "banana":"banane", "orange":"orange", "strawberry":"erdbeere", "pizza":"pizza",
        "burger":"burger", "sausage":"wurst", "steak":"steak", "soup":"suppe",
        "cake":"kuchen", "chocolate":"schokolade", "corn":"mais", "mushroom":"pilz",
        "onion":"zwiebel", "pepper":"paprika", "zucchini":"zucchini", "avocado":"avocado",
        "mango":"mango", "lemon":"zitrone", "salad":"salat", "turkey":"pute",
        "lamb":"lamm", "duck":"ente", "oat":"hafer", "noodle":"nudel",
    ]

    private enum ViewPhase { case source, analyzing, confirm, error }
    private var phase: ViewPhase {
        if isAnalyzing         { return .analyzing }
        if errorMessage != nil { return .error }
        if capturedImage != nil { return .confirm }
        return .source
    }

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
                case .analyzing: analyzingView
                case .confirm:   confirmView
                case .error:     errorView
                }
            }
            .navigationTitle("Mahlzeit per Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onChange(of: photosPickerItem) { _, item in
            guard let item else { return }
            Task { await loadAndAnalyze(item: item) }
        }
        .alert("Kamerazugriff verweigert", isPresented: $showCameraPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte erlaube den Kamerazugriff in den iOS-Einstellungen unter Datenschutz → Kamera.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(isPresented: $showCamera) { image in
                Task { await analyze(image: image) }
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
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.green.opacity(0.8))
            Text("KI-Schätzung: Mengen immer überprüfen!")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button { Task { await requestCameraForPhoto() } } label: {
                    Label("Foto aufnehmen", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    Label("Aus Mediathek wählen", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            Spacer(); Spacer()
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("Mahlzeit wird analysiert…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label("Foto als Referenz nutzen und Lebensmittel manuell hinzufügen", systemImage: "plus.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                    .padding(10).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Vision-Labels als antippbare Chips
                if !detectedLabels.isEmpty {
                    DisclosureGroup(isExpanded: $showLabels) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Antippen um zu suchen:")
                                .font(.caption2).foregroundStyle(.tertiary)
                            FlowLayout(spacing: 6) {
                                ForEach(detectedLabels.prefix(15), id: \.self) { label in
                                    Button {
                                        pickerInitialSearch = Self.en2de[label.lowercased()] ?? label
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
                        Label("Kamera-Labels (\(detectedLabels.count))", systemImage: "eye")
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

                // Manuell hinzufügen
                Button {
                    editingItemID = nil
                    showFoodPicker = true
                } label: {
                    Label("Lebensmittel hinzufügen", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.green)
                }

                let saveable = draftItems.filter { $0.matchedFood != nil }
                let skipped  = draftItems.count - saveable.count
                Button { save() } label: {
                    VStack(spacing: 2) {
                        Text(saveable.isEmpty ? "Keine Einträge zum Speichern" : "Hinzufügen (\(saveable.count) Einträge)")
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
        let matched = item.wrappedValue.matchedFood
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    // Primär: DB-Name wenn gefunden, sonst KI-Name
                    Text(matched?.name ?? item.wrappedValue.name)
                        .font(.subheadline.weight(.medium))
                    if let food = matched {
                        if food.name.lowercased() != item.wrappedValue.name.lowercased() {
                            Text("KI: \u{201E}\(item.wrappedValue.name)\u{201C}")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Nicht gefunden — zum Suchen tippen")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                // Lebensmittel suchen / ändern
                Button {
                    editingItemID = item.wrappedValue.id
                    showFoodPicker = true
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                // Löschen
                Button {
                    draftItems.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            NumericStepperView(value: item.grams, range: 1...5_000, step: 5, unit: "g")
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.circle.fill").font(.system(size: 56)).foregroundStyle(.red)
            Text("Erkennung fehlgeschlagen").font(.headline)
            if let msg = errorMessage {
                Text(msg).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            Button("Nochmal versuchen") {
                capturedImage = nil; draftItems = []; errorMessage = nil
                photosPickerItem = nil; detectedLabels = []
            }
            .buttonStyle(.borderedProminent)
            Spacer(); Spacer()
        }
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
        if let id = editingItemID,
           let idx = draftItems.firstIndex(where: { $0.id == id }) {
            draftItems[idx].matchedFood = food
            draftItems[idx].name        = food.name
            draftItems[idx].grams       = grams
        } else {
            draftItems.append(DraftItem(name: food.name, grams: grams, matchedFood: food))
        }
        editingItemID = nil
    }

    private func loadAndAnalyze(item: PhotosPickerItem) async {
        guard let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await analyze(image: image)
    }

    private func analyze(image: UIImage) async {
        capturedImage = image; isAnalyzing = true; errorMessage = nil
        do {
            let result     = try await PhotoMealRecognizer.recognize(image: image)
            detectedLabels = result.detectedLabels
            var seen       = Set<PersistentIdentifier>()
            draftItems     = result.items.compactMap { item -> DraftItem? in
                guard let food = match(item.name),
                      seen.insert(food.persistentModelID).inserted else { return nil }
                return DraftItem(name: item.name, grams: Double(item.estimatedGrams), matchedFood: food)
            }
            showLabels = draftItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    private func match(_ name: String) -> Food? {
        allFoods
            .filter { $0.source != .recipe && FoodSearch.matches(food: $0, query: name) }
            .sorted { FoodSearch.score(food: $0, query: name) > FoodSearch.score(food: $1, query: name) }
            .first
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: date)
        for item in draftItems {
            guard let food = item.matchedFood, item.grams > 0 else { continue }
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
        let picker = UIImagePickerController()
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
