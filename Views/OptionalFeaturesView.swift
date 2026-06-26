import SwiftUI

// MARK: - OptionalFeaturesView

struct OptionalFeaturesView: View {
    @AppStorage("feature.photoRecognition") private var photoRecognitionEnabled = false
    @AppStorage("feature.bodyMeasurements") private var bodyMeasurementsEnabled = false
    @AppStorage("feature.microNutrients")   private var microNutrientsEnabled   = false
    @AppStorage("feature.calorieCarryover") private var carryoverEnabled        = false

    @AppStorage("geminiApiKey")   private var geminiApiKey   = ""
    @AppStorage("geminiModelID")  private var geminiModelID  = "gemini-2.5-flash"

    @State private var apiKeyVisible = false

    var body: some View {
        List {
            // MARK: Foto-Erkennung
            Section {
                Toggle(isOn: $photoRecognitionEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Foto-Erkennung")
                            .font(.body)
                        Text("Lebensmittel per Foto mit Gemini KI erkennen. Erfordert einen kostenlosen Google AI Studio API-Key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                if photoRecognitionEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gemini API-Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Group {
                                if apiKeyVisible {
                                    TextField("API-Key einfügen", text: $geminiApiKey)
                                } else {
                                    SecureField("API-Key einfügen", text: $geminiApiKey)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                            Button {
                                apiKeyVisible.toggle()
                            } label: {
                                Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if !geminiApiKey.isEmpty {
                            Label("API-Key hinterlegt", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Key kostenlos erhalten: aistudio.google.com → Get API Key")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Modell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Modell-ID", text: $geminiModelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Text("Standard: gemini-2.5-flash — in AI Studio prüfen welches Modell du nutzt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            featureRow(
                title: "Körpermaße tracken",
                description: "Brust, Taille, Hüfte, Bizeps usw. zusätzlich zum Gewicht protokollieren.",
                isOn: $bodyMeasurementsEnabled
            )

            featureRow(
                title: "Mikronährstoffe anzeigen",
                description: "Ballaststoffe, Zucker, gesättigte Fettsäuren und Salz pro Tag im Tagebuch anzeigen.",
                isOn: $microNutrientsEnabled
            )

            featureRow(
                title: "Kalorien-Übertrag",
                description: "Deficit oder Überschuss vom Vortag auf das heutige Ziel anrechnen (max. ±500 kcal). Sichtbar in der Tagesübersicht als 'Übertrag'-Zeile.",
                isOn: $carryoverEnabled
            )
        }
        .navigationTitle("Optionale Features")
        .navigationBarTitleDisplayMode(.large)
    }

    private func featureRow(
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        Section {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
