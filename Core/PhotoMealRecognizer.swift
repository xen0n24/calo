import Foundation
import UIKit

// MARK: - Types

struct RecognizedFoodItem {
    var name:           String
    var estimatedGrams: Int
    var confidence:     Double
}

struct RecognitionResult {
    let items:          [RecognizedFoodItem]
    let detectedLabels: [String]
}

// MARK: - Recognizer

enum PhotoMealRecognizer {

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "geminiApiKey") ?? "" }
    }

    static let modelID = "gemini-2.5-flash-lite"

    static var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: Errors

    enum RecognizerError: LocalizedError {
        case noApiKey
        case imageFailed
        case networkError(Int, String)
        case parseFailed
        case noItemsDetected

        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "Kein Gemini API-Key hinterlegt. Bitte in Profil → Optionale Features eintragen."
            case .imageFailed:
                return "Bild konnte nicht verarbeitet werden."
            case .networkError(let code, let msg):
                return "API-Fehler \(code): \(msg)"
            case .parseFailed:
                return "Antwort konnte nicht verarbeitet werden. Modell-ID prüfen."
            case .noItemsDetected:
                return "Keine Lebensmittel erkannt. Bitte manuell hinzufügen."
            }
        }
    }

    // MARK: Main entry point

    static func recognize(image: UIImage, comment: String = "") async throws -> RecognitionResult {
        guard isAvailable else { throw RecognizerError.noApiKey }

        guard let jpegData = resized(image, maxSide: 1024).jpegData(compressionQuality: 0.5) else {
            throw RecognizerError.imageFailed
        }
        let base64 = jpegData.base64EncodedString()

        let commentLine = comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nZusatzinfo vom Nutzer: \(comment.trimmingCharacters(in: .whitespacesAndNewlines))"

        let prompt = """
        Du bist ein Ernährungs-Experte. Analysiere dieses Foto einer Mahlzeit.\(commentLine)

        Regeln für die Einteilung:
        - Bekannte Gerichte mit eigenem Namen (Pizza, Burger, Döner, Schnitzel, Pasta, Sushi, Kebab usw.) → als EINEN Eintrag mit dem Gerichtnamen
        - Selbst zubereitete Mahlzeiten oder Teller mit mehreren sichtbaren Komponenten (z.B. Hähnchen + Reis + Gemüse) → jede Komponente EINZELN
        - Soßen, Dips und Dressings IMMER als eigenen Eintrag (z.B. Ketchup, Mayonnaise, BBQ-Soße, Salatdressing) — auch wenn nur ein kleiner Klecks sichtbar ist
        - Getränke und Beilagen separat wenn sichtbar
        - Mengen realistisch in Gramm schätzen (typische Portionsgrößen)

        Antworte ausschließlich als JSON ohne weitere Erklärungen:
        {"items":[{"name":"Pizza Margherita","estimatedGrams":350}]}
        Alle Namen auf Deutsch.
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw RecognizerError.parseFailed }

        var request        = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode       = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8)?.prefix(300) ?? "Unbekannter Fehler"
            throw RecognizerError.networkError(statusCode, String(msg))
        }

        // Gemini-Antwort entpacken
        guard
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content    = candidates.first?["content"] as? [String: Any],
            let parts      = content["parts"] as? [[String: Any]],
            let text       = parts.first?["text"] as? String
        else { throw RecognizerError.parseFailed }

        // JSON aus dem Text extrahieren (Markdown-Fences entfernen falls vorhanden)
        let cleaned = extractJSON(from: text)

        guard
            let textData    = cleaned.data(using: .utf8),
            let parsed      = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
            let itemsArray  = parsed["items"] as? [[String: Any]]
        else { throw RecognizerError.parseFailed }

        let items: [RecognizedFoodItem] = itemsArray.compactMap { dict in
            guard
                let name  = dict["name"]           as? String,
                let grams = dict["estimatedGrams"] as? Int
            else { return nil }
            return RecognizedFoodItem(name: name, estimatedGrams: grams, confidence: 0.9)
        }

        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }

        return RecognitionResult(
            items:          items,
            detectedLabels: items.map { $0.name }
        )
    }

    // MARK: Helpers

    /// Entfernt optionale Markdown-Codeblöcke (```json ... ```)
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines  = trimmed.components(separatedBy: "\n")
            let inner  = lines.dropFirst().dropLast().joined(separator: "\n")
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Skaliert ein Bild auf maximal maxSide×maxSide Pixel herunter
    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale  = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
