import Foundation
import VesselCore

/// A packaged product looked up by barcode.
public struct PackagedProduct: Sendable, Equatable, Codable {
    public let barcode: String
    public let name: String
    public let brand: String?
    /// Nutrition per 100 g, as the label states it.
    public let nutrientsPer100g: Nutrients
    /// Serving size in grams, when the label gives one.
    public let servingGrams: Double?
    /// Ingredient and allergen tags, mapped onto Vessel's vocabulary.
    public let tags: [String]
    public let imageURL: URL?

    public var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(brand) \(name)"
    }
}

/// Looks up barcodes against Open Food Facts.
///
/// Chosen over a commercial database because it's free, needs no key, and its
/// data is openly licensed — which matters for an app whose whole premise is
/// that your food log belongs to you.
///
/// Results are cached on disk: scanning the same cereal box every morning
/// should not cost a network round trip, and the app must keep working on a
/// plane.
public actor OpenFoodFactsClient {

    public static let shared = OpenFoodFactsClient()

    public enum LookupError: LocalizedError, Equatable {
        case notFound(String)
        case offline
        case malformedResponse
        case rateLimited

        public var errorDescription: String? {
            switch self {
            case .notFound(let code):
                return "No product found for barcode \(code). You can add it by hand."
            case .offline:
                return "Vessel couldn't reach the product database. Scan again when you're online, or enter it manually."
            case .malformedResponse:
                return "The product database returned something Vessel couldn't read."
            case .rateLimited:
                return "Too many lookups just now — try again in a moment."
            }
        }
    }

    private let session: URLSession
    private var memoryCache: [String: PackagedProduct] = [:]
    private let cacheURL: URL

    /// Open Food Facts asks that clients identify themselves, and throttles
    /// those that don't. Honouring that is the price of a free, open database.
    private static let userAgent = "Vessel/1.4 (iOS; personal food diary; github.com/shankar-sachin/journal)"

    public init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.cacheURL = (caches ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("vessel-barcodes.json")
        // Loading synchronously in the initialiser is fine: the file is small
        // and this happens once, off the first scan rather than at launch.
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: PackagedProduct].self, from: data) {
            memoryCache = decoded
        }
    }

    /// Looks up a barcode, preferring the cache.
    public func product(forBarcode barcode: String) async throws -> PackagedProduct {
        let cleaned = barcode.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { throw LookupError.notFound(barcode) }

        if let cached = memoryCache[cleaned] { return cached }

        // v2 of the API, asking only for the fields we use — the full record is
        // large and most of it is irrelevant here.
        let fields = "product_name,brands,nutriments,serving_quantity,allergens_tags,ingredients_analysis_tags,image_front_small_url"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(cleaned).json?fields=\(fields)") else {
            throw LookupError.notFound(cleaned)
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LookupError.offline
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw LookupError.rateLimited }
            guard http.statusCode == 200 else { throw LookupError.notFound(cleaned) }
        }

        guard let parsed = Self.parse(data, barcode: cleaned) else {
            throw LookupError.notFound(cleaned)
        }

        memoryCache[cleaned] = parsed
        persistCache()
        return parsed
    }

    private func persistCache() {
        // Best-effort: a failed cache write costs one network call later, which
        // isn't worth surfacing to the user.
        guard let data = try? JSONEncoder().encode(memoryCache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Parsing

    /// Open Food Facts is crowd-sourced, so fields are frequently missing,
    /// occasionally the wrong type, and sometimes nonsense. Everything here is
    /// defensive on purpose.
    static func parse(_ data: Data, barcode: String) -> PackagedProduct? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["product"] as? [String: Any]
        else { return nil }

        let name = (product["product_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        let brand = (product["brands"] as? String)?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        /// Values arrive as numbers or as numeric strings depending on who
        /// entered them.
        func value(_ key: String) -> Double {
            if let number = nutriments[key] as? Double { return number }
            if let number = nutriments[key] as? Int { return Double(number) }
            if let text = nutriments[key] as? String { return Double(text) ?? 0 }
            return 0
        }

        // Energy is published in kJ or kcal depending on the region; prefer the
        // kcal field and convert only when it's absent.
        var kcal = value("energy-kcal_100g")
        if kcal == 0 {
            let kilojoules = value("energy_100g")
            if kilojoules > 0 { kcal = kilojoules / 4.184 }
        }

        let nutrients = Nutrients(
            kilocalories: kcal,
            proteinG: value("proteins_100g"),
            carbohydrateG: value("carbohydrates_100g"),
            fatG: value("fat_100g"),
            fiberG: value("fiber_100g"),
            sugarG: value("sugars_100g"),
            saturatedFatG: value("saturated-fat_100g"),
            // Published in grams; Vessel stores sodium in milligrams.
            sodiumMG: value("sodium_100g") * 1000,
            potassiumMG: value("potassium_100g") * 1000,
            calciumMG: value("calcium_100g") * 1000,
            ironMG: value("iron_100g") * 1000,
            vitaminCMG: value("vitamin-c_100g") * 1000
        )

        // A product with no energy value tells the user nothing useful.
        guard nutrients.kilocalories > 0 else { return nil }

        let servingGrams = (product["serving_quantity"] as? Double)
            ?? (product["serving_quantity"] as? String).flatMap(Double.init)

        let allergens = (product["allergens_tags"] as? [String]) ?? []
        let analysis = (product["ingredients_analysis_tags"] as? [String]) ?? []

        return PackagedProduct(
            barcode: barcode,
            name: name,
            brand: brand?.isEmpty == true ? nil : brand,
            nutrientsPer100g: nutrients,
            servingGrams: servingGrams,
            tags: mapTags(allergens: allergens, analysis: analysis),
            imageURL: (product["image_front_small_url"] as? String).flatMap(URL.init(string:))
        )
    }

    /// Maps Open Food Facts' tag vocabulary onto Vessel's.
    ///
    /// Necessary for the Date Log: a correlation across "dairy" only works if
    /// a scanned yoghurt and a database cheese carry the same tag.
    static func mapTags(allergens: [String], analysis: [String]) -> [String] {
        var tags: Set<String> = []

        let allergenMap: [String: String] = [
            "milk": "dairy", "gluten": "gluten", "eggs": "egg", "soybeans": "soy",
            "nuts": "tree nut", "peanuts": "peanut", "sesame-seeds": "sesame",
            "fish": "fish", "crustaceans": "shellfish", "molluscs": "shellfish"
        ]

        for tag in allergens {
            // Tags arrive prefixed by language, e.g. "en:milk".
            let bare = tag.components(separatedBy: ":").last ?? tag
            if let mapped = allergenMap[bare] { tags.insert(mapped) }
            if bare == "milk" { tags.insert("lactose") }
        }

        for tag in analysis where tag.contains("palm-oil") && !tag.contains("free") {
            tags.insert("palm oil")
        }

        return tags.sorted()
    }
}
