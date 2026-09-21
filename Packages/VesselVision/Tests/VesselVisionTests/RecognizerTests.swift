import Testing
import Foundation
@testable import VesselVision
import VesselNutrition

#if canImport(Vision)
import CoreImage
#endif

/// Measured against real photographs.
///
/// A recogniser tested only with mocks proves the plumbing works and nothing
/// about whether it recognises food, which is the entire feature.

#if canImport(Vision)
private func fixture(_ name: String) -> CIImage? {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jpg")
            ?? Bundle.module.url(forResource: name, withExtension: "jpg")
    else { return nil }
    return CIImage(contentsOf: url)
}

@Suite("Food recognition")
struct FoodRecognitionTests {

    private let recognizer = FoodRecognizer()

    @Test("A pizza photo is recognised as pizza")
    func recognisesPizza() async throws {
        let image = try #require(fixture("pizza"), "missing test fixture")
        let reading = await recognizer.read(image: image)

        let labels = reading.candidates.map(\.label).joined(separator: ", ")
        #expect(
            reading.candidates.contains { $0.label.contains("pizza") },
            "expected pizza, got [\(labels)]"
        )
    }

    @Test("Scrambled eggs are recognised")
    func recognisesEggs() async throws {
        let image = try #require(fixture("eggs"))
        let reading = await recognizer.read(image: image)

        let labels = reading.candidates.map(\.label).joined(separator: ", ")
        #expect(
            reading.candidates.contains { $0.label.contains("egg") },
            "expected eggs, got [\(labels)]"
        )
    }

    @Test("A banana is recognised, not discarded as unknown")
    func recognisesBanana() async throws {
        // The regression this guards: a keyword-based filter kept "pizza" but
        // silently threw away banana, apple, broccoli, salmon and most of
        // Vision's real food vocabulary, because none contain a word like
        // "fruit" or "meat".
        let image = try #require(fixture("banana"))
        let reading = await recognizer.read(image: image)

        let labels = reading.candidates.map(\.label).joined(separator: ", ")
        #expect(!reading.candidates.isEmpty, "banana produced no candidates at all")
        #expect(
            reading.candidates.contains { $0.label.contains("banana") || $0.label.contains("fruit") },
            "expected banana or fruit, got [\(labels)]"
        )
    }

    @Test("Recognised foods resolve to real database rows")
    func candidatesResolve() async throws {
        let image = try #require(fixture("pizza"))
        let reading = await recognizer.read(image: image)

        let matched = reading.candidates.compactMap(\.matched)
        #expect(!matched.isEmpty, "a recognised food should map to the database")
        #expect(matched.allSatisfy { $0.nutrientsPer100g.kilocalories > 0 },
                "matched foods should carry real nutrition")
    }

    @Test("Specific labels beat generic ones")
    func specificBeatsGeneric() async throws {
        let image = try #require(fixture("pizza"))
        let reading = await recognizer.read(image: image)

        // "food" is true of every photo here and useless when "pizza" is known.
        if reading.candidates.count > 1 {
            #expect(reading.candidates.first?.label != "food",
                    "a bare 'food' label should not lead when something specific was found")
        }
    }
}
#endif

@Suite("Barcode parsing")
struct OpenFoodFactsParsingTests {

    @Test("A well-formed product parses")
    func parsesProduct() throws {
        let json = """
        {"product":{"product_name":"Oat Crunch","brands":"Acme, Other",
        "nutriments":{"energy-kcal_100g":380,"proteins_100g":9.5,
        "carbohydrates_100g":62,"fat_100g":8.2,"fiber_100g":7,"sugars_100g":12,
        "sodium_100g":0.4},"serving_quantity":45,
        "allergens_tags":["en:gluten","en:milk"]}}
        """
        let product = try #require(
            OpenFoodFactsClient.parse(Data(json.utf8), barcode: "123")
        )

        #expect(product.name == "Oat Crunch")
        #expect(product.brand == "Acme", "only the first brand should be kept")
        #expect(product.nutrientsPer100g.kilocalories == 380)
        // Published in grams, stored in milligrams.
        #expect(product.nutrientsPer100g.sodiumMG == 400)
        #expect(product.servingGrams == 45)
        #expect(product.tags.contains("gluten"))
        #expect(product.tags.contains("dairy"))
        #expect(product.tags.contains("lactose"), "milk implies lactose")
    }

    @Test("Energy in kilojoules is converted")
    func convertsKilojoules() throws {
        // Many European entries publish only kJ.
        let json = """
        {"product":{"product_name":"Biscuit","nutriments":{"energy_100g":2000}}}
        """
        let product = try #require(OpenFoodFactsClient.parse(Data(json.utf8), barcode: "1"))
        #expect(abs(product.nutrientsPer100g.kilocalories - 478) < 1)
    }

    @Test("Numbers written as strings still parse")
    func handlesStringNumbers() throws {
        // Crowd-sourced data is inconsistently typed.
        let json = """
        {"product":{"product_name":"Juice","nutriments":{"energy-kcal_100g":"45","sugars_100g":"10.5"}}}
        """
        let product = try #require(OpenFoodFactsClient.parse(Data(json.utf8), barcode: "2"))
        #expect(product.nutrientsPer100g.kilocalories == 45)
        #expect(product.nutrientsPer100g.sugarG == 10.5)
    }

    @Test("A product with no name or no energy is rejected")
    func rejectsUnusableProducts() {
        // Showing a nameless, calorie-free entry would look like a successful
        // scan of a food that doesn't exist.
        let noName = #"{"product":{"nutriments":{"energy-kcal_100g":100}}}"#
        #expect(OpenFoodFactsClient.parse(Data(noName.utf8), barcode: "3") == nil)

        let noEnergy = #"{"product":{"product_name":"Mystery","nutriments":{}}}"#
        #expect(OpenFoodFactsClient.parse(Data(noEnergy.utf8), barcode: "4") == nil)
    }

    @Test("Garbage input is rejected rather than crashing")
    func rejectsGarbage() {
        #expect(OpenFoodFactsClient.parse(Data("not json".utf8), barcode: "5") == nil)
        #expect(OpenFoodFactsClient.parse(Data(), barcode: "6") == nil)
    }

    @Test("Allergen tags map onto Vessel's vocabulary")
    func mapsAllergens() {
        // The Date Log can only correlate "dairy" if a scanned yoghurt and a
        // database cheese carry the same tag.
        let tags = OpenFoodFactsClient.mapTags(
            allergens: ["en:milk", "en:peanuts", "fr:gluten"],
            analysis: []
        )
        #expect(tags.contains("dairy"))
        #expect(tags.contains("peanut"))
        #expect(tags.contains("gluten"), "language prefixes shouldn't matter")
    }
}
