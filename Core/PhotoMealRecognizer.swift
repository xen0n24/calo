import Foundation
import UIKit

// MARK: - Types

struct RecognizedFoodItem {
    var name:           String
    var estimatedGrams: Int
    var confidence:     Double
    // Nährwerte pro 100g (von Gemini geschätzt)
    var kcalPer100g:    Double
    var proteinPer100g: Double
    var carbsPer100g:   Double
    var fatPer100g:     Double
}

struct RecognitionResult {
    let items:          [RecognizedFoodItem]
    let detectedLabels: [String]
}

// MARK: - Recognizer

enum PhotoMealRecognizer {

    static var apiKey: String {
        UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
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

    // MARK: - Shared prompt fragments

    private static let jsonFormat = """
    {"items":[{"name":"Pizza Margherita","estimatedGrams":350,"kcalPer100g":266,"proteinPer100g":11,"carbsPer100g":33,"fatPer100g":10}]}
    """

    /// Typische Portionsgrößen als Referenz im Prompt
    private static let portionHints = """
    Typische Portionsgrößen (Referenz):
    Döner im Fladenbrot 380g · Chicken Nugget (1 Stück) 17g · Pommes Frites (Portion) 120g · \
    Pizza (1 Stück) 120g · Burger (generisch) 180g · Schnitzel 180g · Hähnchenbrust gebraten 150g · \
    Pasta (Portion gekocht) 220g · Reis (Beilage gekocht) 150g · Brötchen 55g · Brot (Scheibe) 40g · \
    Ketchup 20g · Mayonnaise 15g · Apfel 150g · Banane 120g · Cola (Glas) 250ml · Kaffee 200ml
    """

    // MARK: - Vollständige Mahlzeitanalyse

    static func recognize(image: UIImage, comment: String = "") async throws -> RecognitionResult {
        guard isAvailable else { throw RecognizerError.noApiKey }
        guard let base64 = imageBase64(image) else { throw RecognizerError.imageFailed }

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

        \(portionHints)

        Schätze außerdem die Nährwerte pro 100g für jedes Lebensmittel/Gericht.

        Antworte ausschließlich als JSON ohne weitere Erklärungen:
        \(jsonFormat)
        Alle Namen auf Deutsch. Nährwerte als Zahlen ohne Einheit.
        """

        let itemsArray = try await callGemini(prompt: prompt, base64: base64)
        let items      = parseItems(from: itemsArray)
        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }
        return RecognitionResult(items: items, detectedLabels: items.map { $0.name })
    }

    // MARK: - Einzelnes Lebensmittel per Beschreibung hinzufügen

    static func recognizeSingle(image: UIImage, description: String) async throws -> RecognitionResult {
        guard isAvailable else { throw RecognizerError.noApiKey }
        guard let base64 = imageBase64(image) else { throw RecognizerError.imageFailed }

        let prompt = """
        Du bist ein Ernährungs-Experte. Identifiziere auf dem Foto NUR das folgende Lebensmittel und schätze die sichtbare Menge:
        „\(description)"

        \(portionHints)

        Ignoriere alle anderen Komponenten auf dem Bild vollständig.
        Falls das Lebensmittel nicht eindeutig sichtbar ist, schätze eine realistische Standardportion.
        Schätze außerdem die Nährwerte pro 100g.

        Antworte ausschließlich als JSON ohne weitere Erklärungen:
        \(jsonFormat)
        Name auf Deutsch. Nährwerte als Zahlen ohne Einheit.
        """

        let itemsArray = try await callGemini(prompt: prompt, base64: base64)
        let items      = parseItems(from: itemsArray)
        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }
        return RecognitionResult(items: items, detectedLabels: items.map { $0.name })
    }

    // MARK: - Text-basierte Mahlzeitanalyse (ohne Foto)

    static func recognizeFromText(_ description: String) async throws -> RecognitionResult {
        guard isAvailable else { throw RecognizerError.noApiKey }

        let prompt = """
        Du bist ein Ernährungs-Experte. Der Nutzer hat folgende Mahlzeit beschrieben:
        „\(description)"

        WICHTIGSTE REGEL: Erfasse NUR Lebensmittel, die explizit genannt werden. Ergänze KEINE Beilagen, Getränke oder weitere Produkte, die nicht erwähnt wurden. Wenn jemand nur „Big Mac" schreibt, gibt es nur einen Eintrag: Big Mac. Keine Pommes, keine Cola.

        Für die genannten Lebensmittel:
        1. Typische Portionsgrößen verwenden — bei bekannten Ketten die offiziellen Standardportionen
        2. Wenn ein Kontext erkennbar ist (McDonald's, Burger King, KFC, Subway usw.) → produktspezifische Markennamen behalten
        3. Soßen und Dips die explizit erwähnt werden → als eigenen Eintrag
        4. Getränke die explizit erwähnt werden → als eigenen Eintrag

        \(portionHints)

        Schätze außerdem die Nährwerte pro 100g für jedes Lebensmittel.

        Antworte ausschließlich als JSON ohne weitere Erklärungen:
        \(jsonFormat)
        Markennamen beibehalten (Big Mac, Coca-Cola, Whopper usw.). Sonstige Namen auf Deutsch. Nährwerte als Zahlen ohne Einheit.
        """

        let itemsArray = try await callGemini(prompt: prompt, base64: nil)
        let items      = parseItems(from: itemsArray)
        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }
        return RecognitionResult(items: items, detectedLabels: items.map { $0.name })
    }

    // MARK: - Einzeleintrag per Text hinzufügen (ohne Foto)

    static func recognizeSingleFromText(existingDescription: String, addition: String) async throws -> RecognitionResult {
        guard isAvailable else { throw RecognizerError.noApiKey }

        let prompt = """
        Du bist ein Ernährungs-Experte. Kontext: Der Nutzer hat „\(existingDescription)" gegessen.
        Füge NUR dieses zusätzliche Element hinzu: „\(addition)"

        \(portionHints)

        Schätze Menge und Nährwerte pro 100g für genau dieses eine Element. Markennamen wenn erkennbar beibehalten.

        Antworte ausschließlich als JSON ohne weitere Erklärungen:
        \(jsonFormat)
        Nährwerte als Zahlen ohne Einheit.
        """

        let itemsArray = try await callGemini(prompt: prompt, base64: nil)
        let items      = parseItems(from: itemsArray)
        guard !items.isEmpty else { throw RecognizerError.noItemsDetected }
        return RecognitionResult(items: items, detectedLabels: items.map { $0.name })
    }

    // MARK: - Private Helpers

    private static func imageBase64(_ image: UIImage) -> String? {
        resized(image, maxSide: 1024).jpegData(compressionQuality: 0.5)?.base64EncodedString()
    }

    private static func callGemini(prompt: String, base64: String?) async throws -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = base64 {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]])
        }
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["temperature": 0.2]
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

        guard
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content    = candidates.first?["content"] as? [String: Any],
            let parts      = content["parts"] as? [[String: Any]],
            let text       = parts.first?["text"] as? String
        else { throw RecognizerError.parseFailed }

        let cleaned = extractJSON(from: text)

        guard
            let textData   = cleaned.data(using: .utf8),
            let parsed     = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
            let itemsArray = parsed["items"] as? [[String: Any]]
        else { throw RecognizerError.parseFailed }

        return itemsArray
    }

    private static func parseItems(from itemsArray: [[String: Any]]) -> [RecognizedFoodItem] {
        itemsArray.compactMap { dict in
            guard
                let name  = dict["name"]           as? String,
                let grams = dict["estimatedGrams"] as? Int
            else { return nil }
            // Gemini liefert Int oder Double — beide Varianten abfangen
            func d(_ key: String) -> Double {
                (dict[key] as? Double) ?? (dict[key] as? Int).map { Double($0) } ?? 0
            }
            return RecognizedFoodItem(
                name:           name,
                estimatedGrams: grams,
                confidence:     0.9,
                kcalPer100g:    d("kcalPer100g"),
                proteinPer100g: d("proteinPer100g"),
                carbsPer100g:   d("carbsPer100g"),
                fatPer100g:     d("fatPer100g")
            )
        }
    }

    /// Entfernt optionale Markdown-Codeblöcke (```json ... ```)
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Skaliert ein Bild auf maximal maxSide×maxSide Pixel herunter
    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size    = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale   = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
