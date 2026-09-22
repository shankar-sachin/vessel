import Testing
@testable import VesselNutrition

/// Does a plain word land on the ordinary version of the food?
///
/// The parser hands the resolver bare nouns — "eggs", "chicken", "melon" — and
/// the resolver's first answer is what gets logged unless the user corrects
/// it. Before this set existed, "eggs" resolved to egg yolk, "chicken" to
/// chicken back, "water" to tonic water and "cereal" to Cheerios, and every
/// test still passed, because each checked only that the answer's head noun
/// was right.
///
/// Each case lists every row a person would accept. Written before the ranker
/// was changed, so that the ranker is fitted to the cases and not the other
/// way round.
private let everyday: [(query: String, accept: [String])] = [
    ("eggs", ["Egg, whole"]),
    ("egg", ["Egg, whole"]),
    ("chicken", ["Chicken, NS as to part", "roasted", "Chicken breast"]),
    ("melon", ["cantaloupe", "honeydew"]),
    ("coffee", ["Coffee, brewed", "Coffee, NS as to"]),
    ("tea", ["Tea, hot, leaf, black", "Tea, black", "Tea, hot"]),
    ("bread", ["Bread, white", "Bread, NS as to major flour", "Bread, whole wheat"]),
    ("rice", ["Rice, white, cooked"]),
    ("pasta", ["Pasta, cooked"]),
    ("potato", ["Potato", "Potatoes, baked", "Potato, baked"]),
    ("banana", ["Banana, raw", "Bananas, raw"]),
    ("apple", ["Apple, raw", "Apples, raw"]),
    ("orange", ["Orange, raw", "Oranges, raw"]),
    ("milk", ["Milk"]),
    ("yogurt", ["Yogurt"]),
    ("cheese", ["Cheese"]),
    ("butter", ["Butter"]),
    ("oatmeal", ["Oatmeal"]),
    ("hamburger", ["Hamburger"]),
    ("fries", ["french fries"]),
    ("pancakes", ["Pancakes"]),
    ("croissant", ["Croissant"]),
    ("bagel", ["Bagel"]),
    ("muffin", ["Muffin"]),
    ("burrito", ["Burrito"]),
    ("noodles", ["Noodles, cooked"]),
    ("sausage", ["Sausage"]),
    ("salad", ["Lettuce, salad", "Salad, NS", "Tossed", "Garden"]),
    ("pizza", ["Pizza, cheese"]),
    ("lasagna", ["Lasagna"]),
    ("berries", ["Berries", "Strawberries", "Blueberries"]),
    ("grapes", ["Grapes"]),
    ("strawberries", ["Strawberries"]),
    ("avocado", ["Avocado"]),
    ("broccoli", ["Broccoli"]),
    ("spinach", ["Spinach"]),
    ("almonds", ["Almonds"]),
    ("peanut butter", ["Peanut butter"]),
    ("honey", ["Honey"]),
    ("salmon", ["Salmon"]),
    ("tuna", ["Tuna"]),
    ("tofu", ["Tofu"]),
    ("orange juice", ["Orange juice"]),
    ("chocolate chip cookie", ["Cookie, chocolate chip"]),
    ("scrambled eggs", ["scrambled"]),
    ("boiled egg", ["boiled"]),
    ("chicken breast", ["Chicken breast"]),
    ("brown rice", ["Rice, brown"]),
]

@Suite("Everyday queries land on the ordinary food")
struct EverydayQueryTests {

    private let search = FoodSearch()

    @Test("A bare food word resolves to the version a person means")
    func everydayQueries() {
        var hits = 0
        var misses: [String] = []
        for (query, accept) in everyday {
            let top = search.search(query, limit: 1).first?.food.name ?? "nothing"
            if accept.contains(where: { top.localizedCaseInsensitiveContains($0) }) {
                hits += 1
            } else {
                misses.append("  '\(query)' → \(top)")
            }
        }
        let rate = Double(hits) / Double(everyday.count)
        print(String(format: "EVERYDAY top-1: %.1f%% (%d/%d)", rate * 100, hits, everyday.count))
        for miss in misses { print("   miss:\(miss)") }
        // 85.4% before the ranker learned about "NS as to" clauses and clause
        // typicality; 95.8% after. The two known misses are USDA filing
        // french fries under "Potato," and a green salad under "Lettuce,", so
        // no head-noun ranker can reach them from the bare word.
        #expect(rate >= 0.90, "\(misses.joined(separator: "\n"))")
    }
}
