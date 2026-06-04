import Foundation

// MARK: - API-Datenmodelle

struct OFFNutriments: Decodable, Sendable {
    let energyKcal100g: Double?
    let proteins100g:   Double?
    let carbohydrates100g: Double?
    let fat100g:        Double?
    let fiber100g:      Double?
    let sugars100g:     Double?
    let salt100g:       Double?
    let saturatedFat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g     = "energy-kcal_100g"
        case proteins100g       = "proteins_100g"
        case carbohydrates100g  = "carbohydrates_100g"
        case fat100g            = "fat_100g"
        case fiber100g          = "fiber_100g"
        case sugars100g         = "sugars_100g"
        case salt100g           = "salt_100g"
        case saturatedFat100g   = "saturated-fat_100g"
    }
}

struct OFFProduct: Decodable, Sendable, Identifiable {
    let code:        String?
    let productName: String?
    let brands:      String?
    let nutriments:  OFFNutriments

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case nutriments
    }

    var id: String         { code ?? productName ?? UUID().uuidString }
    var displayName: String { productName?.trimmingCharacters(in: .whitespaces).isEmpty == false
                              ? productName! : "Unbekanntes Produkt" }
    var brandText: String?  { brands?.trimmingCharacters(in: .whitespaces).isEmpty == false ? brands : nil }

    /// Nur Produkte mit gültigen Nährwerten aufnehmen
    var isUsable: Bool {
        (nutriments.energyKcal100g ?? 0) > 0 &&
        !(productName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }
}

// MARK: - Private Response-Wrapper

private struct OFFSingleResponse: Decodable {
    let product: OFFProduct?
}

private struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

// MARK: - Client

enum OpenFoodFactsClient {
    private static let base      = "https://world.openfoodfacts.org"
    private static let userAgent = "Calo-iOS/1.0"

    /// Produkt per Barcode laden
    static func product(barcode: String) async throws -> OFFProduct? {
        let url  = URL(string: "\(base)/api/v2/product/\(barcode).json")!
        let data = try await get(url: url)
        let resp = try JSONDecoder().decode(OFFSingleResponse.self, from: data)
        return resp.product?.isUsable == true ? resp.product : nil
    }

    /// Freitextsuche (bevorzugt deutsche Produkte)
    static func search(query: String) async throws -> [OFFProduct] {
        var comps = URLComponents(string: "\(base)/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms",  value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action",        value: "process"),
            .init(name: "json",          value: "1"),
            .init(name: "page_size",     value: "15"),
            .init(name: "lc",            value: "de"),
            .init(name: "fields",        value: "code,product_name,brands,nutriments"),
        ]
        let data = try await get(url: comps.url!)
        let resp = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return resp.products.filter { $0.isUsable }
    }

    // MARK: Private

    private static func get(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
