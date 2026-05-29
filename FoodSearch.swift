import Foundation

// MARK: - FoodSearch

/// Kapselt den gesamten lokalen Suchalgorithmus:
/// - Token-basiert: "gegrillte Brust" → Tokens ["gegrillte", "brust"]
/// - Deutsche Endungsnormalisierung: "gegrillte" → "gegrillt"
/// - Alias-Suche: food.searchKeywords wird durchsucht
enum FoodSearch {

    // MARK: - Public API

    /// Gibt true zurück wenn food zur query passt.
    static func matches(food: Food, query: String) -> Bool {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return false }
        let haystack = "\(food.name) \(food.searchKeywords)".lowercased()
        return tokens.allSatisfy { token in
            haystack.contains(token) || haystack.contains(normalize(token))
        }
    }

    /// Höherer Score = relevanter. Für Sortierung der Suchergebnisse.
    /// Exakter Match > Prefix > Wortanfang > Substring > Token > Alias-Wortanfang > Alias-Substring
    static func score(food: Food, query: String) -> Int {
        let q        = query.lowercased().trimmingCharacters(in: .whitespaces)
        let name     = food.name.lowercased()
        let keywords = food.searchKeywords.lowercased()
        let tokens   = tokenize(query)

        if name == q                                                          { return 200 }
        if name.hasPrefix(q)                                                  { return 150 }

        // Wortanfang im Namen: "ei" trifft "Ei (hartgekocht)" besser als "Spiegelei"
        let nameWords = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if nameWords.contains(where: { $0.hasPrefix(q) })                    { return 120 }

        if name.contains(q)                                                   { return 50  }

        if tokens.allSatisfy({ t in name.contains(t) || name.contains(normalize(t)) }) { return 20 }

        // Alias/Keywords-Wortanfang
        let kwWords = keywords.components(separatedBy: " ").filter { !$0.isEmpty }
        if kwWords.contains(where: { $0.hasPrefix(q) })                      { return 15  }

        let allText = "\(name) \(keywords)"
        if tokens.allSatisfy({ t in allText.contains(t) || allText.contains(normalize(t)) }) { return 10 }

        return 0
    }

    // MARK: - Private

    /// Query in bereinigte Tokens aufteilen (≥ 2 Zeichen, lowercase).
    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
    }

    /// Deutsche Wortendung abschneiden — längste Endung zuerst prüfen.
    /// Mindest-Restlänge verhindert dass kurze Wörter zerstört werden.
    static func normalize(_ word: String) -> String {
        let suffixes: [(String, Int)] = [
            ("ischen", 4), ("ischer", 4), ("isches", 4), ("ischem", 4), ("ische", 4),
            ("lichen", 4), ("licher", 4), ("liches", 4), ("lichem", 4), ("liche", 4),
            ("ten", 3), ("ter", 3), ("tes", 3), ("tem", 3), ("te", 3),
            ("en", 3), ("er", 3), ("es", 3), ("em", 3), ("e", 3)
        ]
        for (suffix, minRest) in suffixes {
            if word.hasSuffix(suffix) && (word.count - suffix.count) >= minRest {
                return String(word.dropLast(suffix.count))
            }
        }
        return word
    }
}
