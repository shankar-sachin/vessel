import Testing
import Foundation
@testable import VesselNutrition
import VesselCore

/// Run against the real bundled database, not fixtures.
///
/// The thing most likely to be wrong here isn't the code — it's whether the
/// 11,750 rows the builder produced actually answer the questions people ask.
/// A test with a hand-made fixture would pass while "rice" returned rice flour.

@Suite("Database integrity")
struct DatabaseIntegrityTests {

    @Test("The bundled database loads")
    func databaseLoads() {
        #expect(FoodDatabase.shared.isAvailable, "foods.sqlite should be bundled and readable")
        #expect(FoodDatabase.shared.foodCount > 5000, "expected a substantial food table")
    }

    @Test("Staples have believable nutrition")
    func staplesAreSane() throws {
        let search = FoodSearch()

        // Each is a food with a well-known figure. Tolerances are wide enough
        // to allow for variety differences but tight enough to catch a units
        // mix-up or a column misalignment.
        let expectations: [(query: String, kcalRange: ClosedRange<Double>)] = [
            ("whole milk", 55...70),
            ("raw apple", 45...70),
            ("olive oil", 850...920),
            ("cooked white rice", 100...160),
            ("scrambled egg", 130...230)
        ]

        for expectation in expectations {
            let top = try #require(search.search(expectation.query).first,
                                   "no result for '\(expectation.query)'")
            #expect(
                expectation.kcalRange.contains(top.food.nutrientsPer100g.kilocalories),
                "\(expectation.query) → \(top.food.name) at \(top.food.nutrientsPer100g.kilocalories) kcal/100g, outside \(expectation.kcalRange)"
            )
        }
    }

    @Test("Macros are consistent with stated energy")
    func macrosAgreeWithEnergy() {
        // Atwater factors should roughly reproduce the stated calories. A
        // systematic mismatch would mean columns are swapped.
        let foods = FoodDatabase.shared.popularFoods(limit: 300)
        let checkable = foods.filter { $0.nutrientsPer100g.kilocalories > 50 }
        let implausible = checkable.filter { $0.nutrientsPer100g.hasImplausibleEnergy }

        let ratio = Double(implausible.count) / Double(max(1, checkable.count))
        #expect(ratio < 0.25, "\(implausible.count) of \(checkable.count) popular foods have macros that don't match their calories")
    }

    @Test("Densities are physically plausible")
    func densitiesArePlausible() {
        let foods = FoodDatabase.shared.popularFoods(limit: 400)
        for food in foods {
            guard let density = food.density else { continue }
            // Nothing edible is lighter than aerated foam or denser than syrup.
            #expect(density > 0.15 && density < 2.0,
                    "\(food.name) has density \(density) g/ml")
        }
    }
}

@Suite("Search quality")
struct SearchQualityTests {

    private let search = FoodSearch()

    /// Asserts that one of the top `within` results looks like what was meant.
    private func expectTop(_ query: String, contains needle: String, within: Int = 3) {
        let results = search.search(query, limit: within)
        let names = results.map(\.food.name)
        #expect(
            names.contains { $0.localizedCaseInsensitiveContains(needle) },
            "'\(query)' → \(names). Expected something containing '\(needle)' in the top \(within)."
        )
    }

    @Test("Single-word staples find the staple, not a derivative")
    func staplesRankFirst() {
        expectTop("rice", contains: "Rice")
        expectTop("milk", contains: "Milk")
        expectTop("banana", contains: "Banana")
        expectTop("chicken breast", contains: "Chicken")
        expectTop("broccoli", contains: "Broccoli")
    }

    @Test("Word order doesn't matter")
    func wordOrderIsFlexible() {
        // USDA writes "Rice, white, cooked"; people say "cooked white rice".
        expectTop("cooked white rice", contains: "Rice")
        expectTop("white rice", contains: "Rice")
    }

    @Test("Partial words match while typing")
    func prefixMatching() {
        expectTop("brocc", contains: "Broccoli")
        expectTop("chick", contains: "Chick")
    }

    @Test("Nonsense returns nothing rather than something wrong")
    func nonsenseReturnsEmpty() {
        // Offering a confident wrong answer is worse than offering none.
        #expect(search.search("zzzzqqqq").isEmpty)
        #expect(search.search("x").isEmpty, "single characters are too ambiguous to search")
    }

    @Test("Results carry usable portions")
    func resultsHavePortions() throws {
        let rice = try #require(search.search("cooked white rice").first)
        #expect(!rice.food.portions.isEmpty, "rice should list household measures")
        #expect(rice.food.defaultPortion != nil)
    }

    @Test("Empty query offers real staples, not database oddities")
    func suggestionsAreUseful() {
        let suggestions = search.suggestions(limit: 20)
        #expect(suggestions.count == 20)
        #expect(suggestions.allSatisfy { $0.food.nutrientsPer100g.kilocalories > 0 })

        let names = suggestions.map { $0.food.name.lowercased() }

        // Things people actually log should be near the top.
        let expected = ["milk", "egg", "bread", "rice", "chicken", "apple", "banana", "coffee"]
        let found = expected.filter { staple in names.contains { $0.contains(staple) } }
        #expect(found.count >= 4,
                "expected common staples in the first 20 suggestions, got: \(names)")

        // And the curiosities should not be.
        for oddity in ["bear", "flan", "dal"] {
            #expect(!names.contains { $0 == oddity },
                    "'\(oddity)' should not lead the suggestion list")
        }
    }
}

@Suite("Ingredient tagging")
struct TaggingTests {

    private let search = FoodSearch()

    private func tags(for query: String) -> [String] {
        search.search(query).first?.food.tags ?? []
    }

    @Test("Dairy foods are tagged dairy")
    func dairyTagged() {
        #expect(tags(for: "whole milk").contains("dairy"))
        #expect(tags(for: "cheddar cheese").contains("dairy"))
    }

    @Test("Plant milks are not tagged dairy")
    func plantMilksAreNotDairy() {
        // Telling someone avoiding dairy that their almond milk is dairy is
        // worse than saying nothing at all.
        #expect(!tags(for: "almond milk").contains("dairy"))
        #expect(!tags(for: "soy milk").contains("dairy"))
    }

    @Test("Wheat foods are tagged gluten")
    func glutenTagged() {
        #expect(tags(for: "whole wheat bread").contains("gluten"))
    }

    @Test("Gluten-free grains are never tagged gluten")
    func glutenFreeGrainsAreSafe() {
        // The failure this guards against is not hypothetical: USDA files every
        // grain under "Cereal Grains and Pasta", which once tagged plain white
        // rice as containing gluten and wheat.
        for grain in ["white rice", "brown rice", "quinoa", "corn", "buckwheat"] {
            guard let food = search.search(grain).first?.food else { continue }
            #expect(!food.tags.contains("gluten"),
                    "\(food.name) must not be tagged gluten")
            #expect(!food.tags.contains("wheat"),
                    "\(food.name) must not be tagged wheat")
        }
    }

    @Test("Foods named after pasta but made of vegetables aren't gluten")
    func spaghettiSquashIsNotPasta() {
        guard let squash = search.search("spaghetti squash").first?.food else { return }
        #expect(!squash.tags.contains("gluten"), "\(squash.name) is a vegetable")
    }
}

@Suite("Portion resolution")
struct PortionResolverTests {

    private let resolver = PortionResolver()
    private let search = FoodSearch()

    @Test("A direct weight needs no conversion")
    func directWeight() throws {
        let food = try #require(search.search("whole milk").first).food
        let result = try #require(resolver.grams(quantity: 150, unit: .gram, food: food))
        #expect(result.grams == 150)
        #expect(result.basis == .weight)
        #expect(!result.isEstimate)
    }

    @Test("Ounces convert correctly")
    func ounces() throws {
        let food = try #require(search.search("whole milk").first).food
        let result = try #require(resolver.grams(quantity: 2, unit: .ounce, food: food))
        #expect(abs(result.grams - 56.7) < 0.5)
    }

    @Test("A cup of rice weighs far more than a cup of milk would suggest")
    func perFoodVolumeConversion() throws {
        let rice = try #require(search.search("cooked white rice").first).food
        let result = try #require(resolver.grams(quantity: 1, unit: .cup, food: rice))

        // A cup of cooked rice is roughly 150–200 g. Falling back to water's
        // density would give ~237 g, which is the bug this guards against.
        #expect(result.grams > 120 && result.grams < 220,
                "1 cup of \(rice.name) resolved to \(result.grams) g")

        // Rice ships a measured "1 cup, cooked" portion, so this route is a
        // lookup rather than a guess and must not be labelled an estimate.
        if case .namedPortion = result.basis {
            #expect(!result.isEstimate, "a measured portion is not an estimate")
        } else {
            #expect(result.isEstimate, "anything other than a measured portion is an estimate")
        }
    }

    @Test("A food with no portion data still converts, and says it's guessing")
    func densityFallbackIsFlagged() throws {
        // Built by hand: the point is the path taken when the database knows
        // nothing about this food's measures.
        let bare = FoodRecord(
            id: "test:1", name: "Mystery soup", category: "", source: "legacy",
            popularity: 1, density: nil,
            nutrientsPer100g: Nutrients(kilocalories: 40),
            portions: [], tags: []
        )
        let result = try #require(resolver.grams(quantity: 1, unit: .cup, food: bare))
        #expect(result.basis == .assumption)
        #expect(result.isEstimate)
        // Falls back to water, which is the honest default for an unknown liquid.
        #expect(abs(result.grams - 236.6) < 1)
    }

    @Test("Quantities scale linearly")
    func quantitiesScale() throws {
        let food = try #require(search.search("cooked white rice").first).food
        let single = try #require(resolver.grams(quantity: 1, unit: .cup, food: food))
        let double = try #require(resolver.grams(quantity: 2, unit: .cup, food: food))
        #expect(abs(double.grams - single.grams * 2) < 0.01)
    }

    @Test("Zero and negative quantities resolve to nothing")
    func rejectsNonPositive() throws {
        let food = try #require(search.search("whole milk").first).food
        #expect(resolver.grams(quantity: 0, unit: .cup, food: food) == nil)
        #expect(resolver.grams(quantity: -1, unit: .gram, food: food) == nil)
    }

    @Test("Nutrition scales with the resolved weight")
    func nutritionScales() throws {
        let food = try #require(search.search("whole milk").first).food
        let per100 = food.nutrientsPer100g.kilocalories
        let scaled = food.nutrients(forGrams: 250).kilocalories
        #expect(abs(scaled - per100 * 2.5) < 0.01)
    }
}

@Suite("Default portions")
struct DefaultPortionTests {

    private let search = FoodSearch()

    @Test("Staples open on an ordinary household measure")
    func defaultsAreOrdinary() throws {
        // USDA's own portion order is unreliable here: milk's first listed
        // measure is "1 individual school container".
        let oddities = ["school", "container", "package", "individual", "guideline"]

        for query in ["whole milk", "cooked white rice", "cheddar cheese", "raw apple"] {
            guard let food = search.search(query).first?.food,
                  let portion = food.defaultPortion else { continue }
            let lowered = portion.label.lowercased()
            #expect(
                !oddities.contains { lowered.contains($0) },
                "\(food.name) opens on '\(portion.label)', which isn't how people measure food"
            )
        }
    }

    @Test("Portions never include USDA's advisory rows")
    func noAdvisoryPortions() {
        for food in FoodDatabase.shared.popularFoods(limit: 300) {
            for portion in food.portions {
                let lowered = portion.label.lowercased()
                #expect(!lowered.hasPrefix("guideline amount"),
                        "\(food.name) lists '\(portion.label)' as a portion")
                #expect(!lowered.contains("quantity not specified"))
            }
        }
    }
}

@Suite("Variants and accompaniments")
struct VariantTests {

    private let search = FoodSearch()
    private let accompaniments = Accompaniments()

    @Test("Ambiguity is derived from the corpus, not from a list")
    func ambiguityIsDerived() {
        // "Milk" spans 32 to 496 kcal per 100 g across 64 rows, so it asks.
        // "Banana" spans two rows, so it doesn't. Neither fact is written down
        // anywhere — both are computed from the data at build time, which is
        // why this also works for the other four hundred ambiguous heads
        // nobody enumerated.
        #expect(FoodDatabase.shared.isAmbiguousHead("milk"))
        #expect(FoodDatabase.shared.isAmbiguousHead("bread"))
        #expect(!FoodDatabase.shared.isAmbiguousHead("banana"))
        #expect(!FoodDatabase.shared.isAmbiguousHead("avocado"))
    }

    @Test("A bare 'milk' offers its variants")
    func milkOffersVariants() {
        let matches = search.search("milk", limit: 8)
        let options = FoodVariants.options(query: "milk", matches: matches)
        #expect(options.count >= 2, "expected milk variants, got \(options.map(\.name))")

        // And they must actually differ in a way worth asking about.
        let energies = options.map(\.nutrientsPer100g.kilocalories)
        if let low = energies.min(), let high = energies.max(), high > 0 {
            #expect((high - low) / high > 0.15, "variants that barely differ aren't worth a tap")
        }
    }

    @Test("A specific phrasing doesn't ask")
    func specificPhrasingIsNotAmbiguous() {
        // "whole milk" already answered the question.
        let matches = search.search("whole milk", limit: 8)
        #expect(FoodVariants.options(query: "whole milk", matches: matches).isEmpty)
    }

    @Test("Variant labels drop the repeated head noun")
    func labelsAreDistinguishing() throws {
        let matches = search.search("milk", limit: 8)
        let options = FoodVariants.options(query: "milk", matches: matches)
        let first = try #require(options.first)
        let label = FoodVariants.distinguishingLabel(for: first, term: "milk")
        // A picker of buttons all reading "Milk, …" would be noise.
        #expect(!label.isEmpty)
        #expect(label.lowercased() != first.name.lowercased())
    }

    @Test("Companions are mined from the corpus")
    func companionsAreMined() throws {
        // Pasta with sauce is recorded dozens of times in FoodData Central's
        // survey composites. Nobody wrote that down here.
        let pasta = try #require(FoodDatabase.shared.companion(forHead: "pasta"))
        #expect(pasta.occurrences >= 2)
        #expect(!pasta.companion.isEmpty)
    }

    @Test("A companion already in the meal isn't offered again")
    func suggestionRespectsWhatsThere() throws {
        guard let mined = FoodDatabase.shared.companion(forHead: "pasta") else { return }
        let suggestion = accompaniments.suggestion(
            for: "Pasta, cooked",
            alreadyLogged: [mined.companion]
        )
        #expect(suggestion == nil, "offering what's already logged is noise")
    }

    @Test("Foods with nothing recorded alongside them suggest nothing")
    func noSuggestionWithoutEvidence() {
        // The honest outcome when the data doesn't support a guess — which is
        // exactly what it says about cereal and milk.
        #expect(accompaniments.suggestion(for: "Banana, raw") == nil)
    }
}
