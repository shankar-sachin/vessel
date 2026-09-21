import Foundation

/// Assigns ingredient and allergen tags from a food's name and category.
///
/// These tags are what the Date Log's correlation engine actually groups on.
/// Without them the engine can only ever say "pizza correlates with bloating",
/// which isn't actionable — the useful finding is "dairy does", and that only
/// emerges if every cheese, milk and butter entry carries the same tag.
///
/// Deliberately keyword rules rather than a model: they're inspectable, fixable
/// in one line when wrong, and a wrong tag here quietly corrupts a health
/// conclusion, so being able to see exactly why something was tagged matters
/// more than squeezing out the last few percent of coverage.
enum Tagging {

    /// tag → substrings that imply it.
    private static let rules: [String: [String]] = [
        // Named varieties are listed explicitly because tags are matched
        // against the food's *name* only — see `tags(forName:category:)`.
        "dairy": ["milk", "cheese", "yogurt", "yoghurt", "cream", "butter", "whey",
                  "custard", "ice cream", "kefir", "ghee", "curd", "casein",
                  "cheddar", "mozzarella", "parmesan", "brie", "feta", "gouda",
                  "ricotta", "provolone", "swiss", "monterey jack", "colby",
                  "camembert", "mascarpone", "havarti", "gruyere", "queso"],
        "lactose": ["milk", "cheese", "yogurt", "yoghurt", "cream", "ice cream", "kefir",
                    "cheddar", "mozzarella", "ricotta", "queso"],
        "gluten": ["wheat", "bread", "pasta", "barley", "rye", "cracker",
                   "couscous", "seitan", "bulgur", "farro", "semolina",
                   "biscuit", "cake", "cookie", "pastry", "pizza", "bagel",
                   "noodle", "muffin", "pretzel", "waffle", "pancake", "crouton",
                   "spaghetti", "macaroni", "lasagna", "ravioli", "doughnut", "donut"],
        "wheat": ["wheat", "flour", "bread", "pasta", "semolina", "bulgur", "couscous"],
        "egg": ["egg"],
        "soy": ["soy", "tofu", "edamame", "tempeh", "miso"],
        "peanut": ["peanut"],
        "tree nut": ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut",
                     "macadamia", "brazil nut", "pine nut"],
        "sesame": ["sesame", "tahini"],
        "fish": ["salmon", "tuna", "cod", "haddock", "sardine", "anchovy", "mackerel",
                 "trout", "halibut", "tilapia", "herring", "fish"],
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster",
                      "scallop", "squid", "octopus"],
        "allium": ["onion", "garlic", "leek", "shallot", "scallion", "chive"],
        "nightshade": ["tomato", "potato", "eggplant", "aubergine", "pepper, sweet",
                       "chili", "chilli", "paprika", "cayenne"],
        "caffeine": ["coffee", "espresso", "tea", "cola", "energy drink", "matcha",
                     "chocolate", "cocoa"],
        "alcohol": ["beer", "wine", "liquor", "vodka", "whiskey", "whisky", "rum",
                    "gin", "tequila", "cider, hard", "champagne"],
        "legume": ["bean", "lentil", "chickpea", "pea", "hummus"],
        "cruciferous": ["broccoli", "cauliflower", "cabbage", "brussels sprout",
                        "kale", "bok choy", "collard"],
        "spicy": ["chili", "chilli", "jalapeno", "sriracha", "cayenne", "hot sauce",
                  "curry", "wasabi", "horseradish"],
        "artificial sweetener": ["aspartame", "sucralose", "saccharin", "stevia",
                                 "sugar-free", "sugar free", "diet "],
        "fried": ["fried", "deep-fried", "tempura"],
        "processed meat": ["bacon", "sausage", "salami", "ham", "hot dog", "pepperoni",
                           "bologna", "prosciutto", "chorizo", "jerky"]
    ]

    /// Substrings that *cancel* a tag matched above.
    ///
    /// Without these, every non-dairy substitute gets tagged as the thing it
    /// exists to replace — and telling someone avoiding dairy that their oat
    /// milk is dairy is worse than telling them nothing.
    /// Grains that contain gluten, matched as whole words.
    ///
    /// Whole words, not substrings: "buckwheat" contains "wheat" but is a
    /// gluten-free seed, and substring matching gets that exactly backwards.
    private static let glutenGrainWords: Set<String> = [
        "wheat", "barley", "rye", "spelt", "semolina", "durum", "farro",
        "bulgur", "couscous", "seitan", "triticale", "kamut", "malt", "farina"
    ]

    /// Grains and starches that contain none.
    private static let glutenFreeGrainWords: Set<String> = [
        "rice", "corn", "maize", "quinoa", "millet", "sorghum", "teff",
        "amaranth", "buckwheat", "polenta", "grits", "hominy", "tapioca",
        "cornmeal", "cornstarch"
    ]

    private static let exclusions: [String: [String]] = [
        "dairy":   ["soy milk", "almond milk", "oat milk", "rice milk", "coconut milk",
                    "cashew milk", "hemp milk", "non-dairy", "nondairy", "dairy-free",
                    "dairy free", "milk thistle", "milkweed", "peanut butter",
                    "apple butter", "cocoa butter", "shea butter", "milk chocolate, substitute"],
        "lactose": ["lactose free", "lactose-free", "soy milk", "almond milk", "oat milk",
                    "rice milk", "coconut milk", "non-dairy", "nondairy"],
        "gluten":  ["gluten free", "gluten-free", "rice flour", "corn flour",
                    "almond flour", "coconut flour", "rice noodle",
                    "corn tortilla", "rice cracker",
                    // Named after pasta, made of neither wheat nor pasta.
                    "spaghetti squash", "spaghetti sauce", "pizza sauce",
                    "marinara"],
        "wheat":   ["buckwheat", "gluten free", "gluten-free",
                    "spaghetti squash", "spaghetti sauce"],
        "egg":     ["eggplant", "egg substitute", "egg replacer"],
        "caffeine": ["decaf", "decaffeinated", "herbal tea", "chamomile", "rooibos",
                     "white chocolate"],
        "alcohol": ["non-alcoholic", "nonalcoholic", "alcohol-free", "sugar alcohol"],
        "peanut":  ["peanut-free"],
        "nightshade": ["sweet potato", "pepper, black", "peppercorn"]
    ]

    /// Tags for a food.
    ///
    /// Matched against the **name only**, deliberately. USDA's categories are far
    /// too coarse to imply an ingredient: every grain on earth sits under
    /// "Cereal Grains and Pasta", which tagged plain white rice as containing
    /// gluten and wheat. Telling someone with coeliac disease that rice has
    /// gluten is worse than telling them nothing, so the category is ignored and
    /// the keyword lists carry named varieties instead.
    ///
    /// - Parameter category: accepted for callers' convenience and for future
    ///   rules that can use it safely; no current rule does.
    static func tags(forName name: String, category: String) -> Set<String> {
        let haystack = name.lowercased()
        var result: Set<String> = []

        for (tag, needles) in rules {
            guard needles.contains(where: { haystack.contains($0) }) else { continue }
            if let blocked = exclusions[tag], blocked.contains(where: { haystack.contains($0) }) {
                continue
            }
            result.insert(tag)
        }

        // Backstop: a food made from a gluten-free grain, with no gluten grain
        // anywhere in its name, is gluten free — whatever else the keywords
        // matched.
        //
        // This runs on whole words against the full name, because USDA writes
        // names comma-inverted. "Flour, rice, white" never contains the literal
        // substring "rice flour", so a phrase-based exclusion misses it and the
        // word "flour" alone tags it wheat.
        let words = Set(haystack.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let hasGlutenGrain = !words.isDisjoint(with: glutenGrainWords)
        let hasGlutenFreeGrain = !words.isDisjoint(with: glutenFreeGrainWords)

        if hasGlutenFreeGrain && !hasGlutenGrain {
            result.remove("gluten")
            result.remove("wheat")
        }
        return result
    }
}
