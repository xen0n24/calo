import SwiftUI

// MARK: - OptionalFeaturesView

struct OptionalFeaturesView: View {
    @AppStorage("feature.photoRecognition") private var photoRecognitionEnabled = false
    @AppStorage("feature.bodyMeasurements") private var bodyMeasurementsEnabled = false
    @AppStorage("feature.microNutrients")   private var microNutrientsEnabled   = false
    @AppStorage("feature.calorieCarryover") private var carryoverEnabled        = false

    var body: some View {
        List {
            featureRow(
                title: "Foto-Erkennung",
                description: "Lebensmittel per Foto erkennen mit On-Device-KI. Erfordert iPhone 15 Pro oder neuer mit aktivierter Apple Intelligence.",
                isOn: $photoRecognitionEnabled
            )

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

    // Neue Features: einfach eine weitere featureRow(...)-Zeile hinzufügen.
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
