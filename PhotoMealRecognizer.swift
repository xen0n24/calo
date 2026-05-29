import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Structured output types

#if canImport(FoundationModels)
@Generable
struct FoodRecognitionResponse {
    @Guide(description: "Erkannte Lebensmittel mit Mengenangaben in Gramm")
    var items: [RecognizedFoodItem]
}

@Generable
struct RecognizedFoodItem {
    @Guide(description: "Lebensmittel-Name auf Deutsch, z.B. 'Hähnchenbrust'")
    var name: String
    @Guide(description: "Geschätzte Menge in Gramm")
    var estimatedGrams: Int
    @Guide(description: "Konfidenz 0.0–1.0")
    var confidence: Double
}
#else
struct RecognizedFoodItem {
    var name: String
    var estimatedGrams: Int
    var confidence: Double
}
#endif

struct RecognitionResult {
    let items:          [RecognizedFoodItem]
    let detectedLabels: [String]
}

// MARK: - Recognizer

enum PhotoMealRecognizer {

    enum RecognizerError: LocalizedError {
        case modelUnavailable, visionFailed, noItemsDetected
        var errorDescription: String? {
            switch self {
            case .modelUnavailable: return "Apple Intelligence ist auf diesem Gerät nicht verfügbar."
            case .visionFailed:     return "Bild konnte nicht verarbeitet werden."
            case .noItemsDetected:  return "Keine Lebensmittel erkannt. Bitte manuell hinzufügen."
            }
        }
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        SystemLanguageModel.default.availability == .available
        #else
        false
        #endif
    }

    #if canImport(FoundationModels)
    // Zu generisch — verwirren FM mehr als sie helfen
    private static let genericLabels: Set<String> = [
        "food", "dish", "meal", "cuisine", "produce", "ingredient",
        "vegetable", "fruit", "meat", "seafood", "dairy", "plant",
        "plate", "bowl", "table", "fast food", "junk food", "snack food",
        "natural foods", "whole food", "recipe", "staple food"
    ]
    #endif

    static func recognize(image: UIImage) async throws -> RecognitionResult {
        #if canImport(FoundationModels)
        guard isAvailable else { throw RecognizerError.modelUnavailable }

        let visionLabels = try await classifyWithVision(image)
        guard !visionLabels.isEmpty else { throw RecognizerError.visionFailed }

        // Nur spezifische Labels ans FM — Top 8 reichen, kurzer Prompt = kein Overflow
        let specific  = visionLabels.filter { !genericLabels.contains($0.name.lowercased()) }
        let labelText = specific.prefix(8).map { $0.name }.joined(separator: ", ")

        let prompt       = "Vision-Labels: \(labelText). Lebensmittel auf Deutsch mit typischen Gramm-Mengen. Frittiertes als eigene Position. Farb-/Textur-Fehlklassifikationen korrigieren."
        let instructions = "Ernährungs-Analyst. Lebensmittel aus Vision-Labels auf Deutsch identifizieren, realistische Portionsgrößen schätzen. Keine versteckten Zutaten."

        let session  = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: FoodRecognitionResponse.self)

        let items = response.content.items
        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }

        return RecognitionResult(items: items, detectedLabels: visionLabels.map { $0.name })
        #else
        throw RecognizerError.modelUnavailable
        #endif
    }

    // MARK: - Vision (immer verfügbar)

    private struct LabelResult { let name: String; let confidence: Float }

    private static func classifyWithVision(_ image: UIImage) async throws -> [LabelResult] {
        guard let ciImage = CIImage(image: image) else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage)
            try handler.perform([request])
            return (request.results ?? [])
                .filter { $0.confidence > 0.10 }
                .prefix(15)
                .map { LabelResult(name: $0.identifier, confidence: $0.confidence) }
        }.value
    }
}
