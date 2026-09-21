import Foundation

/// Reads one extracted FoodData Central dataset directory.
struct DatasetLoader {

    let directory: URL
    let source: DataSource

    /// Known volume units, in millilitres, for deriving density from a portion.
    private static let volumeUnits: [(needle: String, ml: Double)] = [
        ("fl oz", 29.5735295625),
        ("cup", 236.5882365),
        ("tablespoon", 14.78676478125),
        ("tbsp", 14.78676478125),
        ("teaspoon", 4.92892159375),
        ("tsp", 4.92892159375),
        ("liter", 1000),
        ("litre", 1000),
        ("milliliter", 1),
        ("millilitre", 1),
        ("pint", 473.176473),
        ("quart", 946.352946),
        ("gallon", 3785.411784)
    ]

    func load() throws -> [FoodRow] {
        let categories = try loadCategories()
        var foods = try loadFoods(categories: categories)
        guard !foods.isEmpty else { return [] }

        let index = Dictionary(uniqueKeysWithValues: foods.enumerated().map { ($0.element.fdcID, $0.offset) })
        let nutrientMap = try loadNutrientMap()
        try loadNutrients(into: &foods, index: index, nutrientMap: nutrientMap)
        try loadPortions(into: &foods, index: index)

        // A food with no energy value is almost always an incomplete record and
        // would show as "0 kcal", which is worse than not offering it at all.
        return foods.filter { $0.kilocalories > 0 }
    }

    // MARK: - Pieces

    private func loadCategories() throws -> [Int: String] {
        // FNDDS uses its own category table; the others use food_category.
        for name in ["food_category.csv", "wweia_food_category.csv"] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let rows = try CSVReader.rows(at: url)
            var result: [Int: String] = [:]
            for row in rows {
                guard let id = row.int(0) else { continue }
                // food_category: id, code, description. wweia: id, description.
                result[id] = name.hasPrefix("wweia") ? row.field(1) : row.field(2)
            }
            if !result.isEmpty { return result }
        }
        return [:]
    }

    private func loadFoods(categories: [Int: String]) throws -> [FoodRow] {
        let rows = try CSVReader.rows(at: directory.appendingPathComponent("food.csv"))
        let wanted = expectedDataType

        return rows.compactMap { row in
            guard row.field(1) == wanted,
                  let fdcID = row.int(0)
            else { return nil }

            let rawName = row.field(2).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { return nil }

            let category = row.int(3).flatMap { categories[$0] } ?? ""
            let name = Curation.cleanName(rawName)
            guard Curation.isUsable(name: name) else { return nil }

            return FoodRow(
                id: "fdc:\(fdcID)",
                fdcID: fdcID,
                name: name,
                searchName: Curation.searchName(name),
                category: category,
                source: source,
                tags: Tagging.tags(forName: rawName, category: category)
            )
        }
    }

    private var expectedDataType: String {
        switch source {
        case .foundation: return "foundation_food"
        case .survey:     return "survey_fndds_food"
        case .legacy:     return "sr_legacy_food"
        }
    }

    /// Maps whatever number a dataset uses in `food_nutrient.nutrient_id` onto
    /// the modern FoodData Central nutrient id.
    ///
    /// Necessary because the datasets disagree. SR Legacy and Foundation store
    /// the modern id (1008 = Energy); FNDDS stores the *legacy* `nutrient_nbr`
    /// in the same column (208 = Energy). Reading FNDDS with the modern ids
    /// matches nothing at all, which silently drops the best-named 5,400 foods
    /// in the whole build — it looks like a filtering bug rather than a schema
    /// mismatch, so it's worth the extra pass to handle properly.
    private func loadNutrientMap() throws -> [Int: Int] {
        let url = directory.appendingPathComponent("nutrient.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        var map: [Int: Int] = [:]
        var byNumber: [Int: Int] = [:]

        for row in try CSVReader.rows(at: url) {
            guard let id = row.int(0) else { continue }
            map[id] = id

            // Only index legacy numbers for nutrients we actually track, and
            // never overwrite one already claimed.
            //
            // Legacy numbers are NOT unique: 205 belongs to both 1005
            // "Carbohydrate, by difference" (what every nutrition label means)
            // and 1050 "Carbohydrate, by summation". Taking whichever appeared
            // last in the file silently mapped every carbohydrate reading to an
            // untracked nutrient, and every FNDDS food came out with 0 g carbs.
            guard NutrientID.all.contains(id) else { continue }
            if let number = row.double(3).map({ Int($0) }), byNumber[number] == nil {
                byNumber[number] = id
            }
        }

        // A real id always beats a legacy number that happens to collide with it.
        return byNumber.merging(map) { _, actualID in actualID }
    }

    private func loadNutrients(
        into foods: inout [FoodRow],
        index: [Int: Int],
        nutrientMap: [Int: Int]
    ) throws {
        let rows = try CSVReader.rows(at: directory.appendingPathComponent("food_nutrient.csv"))
        for row in rows {
            guard let fdcID = row.int(1),
                  let position = index[fdcID],
                  let rawID = row.int(2),
                  let nutrientID = nutrientMap[rawID] ?? (NutrientID.all.contains(rawID) ? rawID : nil),
                  NutrientID.all.contains(nutrientID),
                  let amount = row.double(3)
            else { continue }
            foods[position].nutrients[nutrientID] = amount
        }
    }

    private func loadPortions(into foods: inout [FoodRow], index: [Int: Int]) throws {
        let url = directory.appendingPathComponent("food_portion.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let units = try loadMeasureUnits()
        let rows = try CSVReader.rows(at: url)

        for row in rows {
            guard let fdcID = row.int(1),
                  let position = index[fdcID],
                  let grams = row.double(7), grams > 0
            else { continue }

            guard let label = portionLabel(row: row, units: units) else { continue }
            foods[position].portions.append(Portion(label: label, grams: grams))

            if let density = density(label: label, grams: grams) {
                // Keep the first sensible density; portions are ordered by
                // seq_num, so the earliest is the most representative.
                if foods[position].density == nil { foods[position].density = density }
            }
        }

        for position in foods.indices {
            foods[position].portions = Curation.tidy(portions: foods[position].portions)
        }
    }

    private func loadMeasureUnits() throws -> [Int: String] {
        let url = directory.appendingPathComponent("measure_unit.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var result: [Int: String] = [:]
        for row in try CSVReader.rows(at: url) {
            guard let id = row.int(0) else { continue }
            result[id] = row.field(1)
        }
        return result
    }

    /// Builds a human label from whichever fields this dataset populates.
    ///
    /// FNDDS puts the text in `portion_description` ("1 cup"); SR Legacy leaves
    /// that empty and puts it in `modifier` with the count in `amount`.
    private func portionLabel(row: [String], units: [Int: String]) -> String? {
        let description = row.field(5).trimmingCharacters(in: .whitespaces)
        if !description.isEmpty {
            // FNDDS uses this placeholder for "no portion given".
            guard !description.lowercased().contains("quantity not specified") else { return nil }
            return description
        }

        let modifier = row.field(6).trimmingCharacters(in: .whitespaces)
        // SR Legacy's modifier is sometimes a bare numeric code, not words.
        guard !modifier.isEmpty, Int(modifier) == nil else { return nil }

        let amount = row.double(3) ?? 1
        let unitName = row.int(4).flatMap { units[$0] } ?? ""
        let quantity = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2g", amount)

        let parts = [quantity, unitName, modifier].filter { !$0.isEmpty && $0 != "undetermined" }
        return parts.joined(separator: " ")
    }

    /// Grams per millilitre, if the label is a plain volume measure.
    ///
    /// The label must *begin* with an optional quantity and then the unit —
    /// "1 cup", "0.5 cup", "1 fl oz". Merely containing a unit word is not
    /// enough, because FNDDS ships rows like "Guideline amount per cup of hot
    /// cereal", which is advice about cereal rather than a portion of the food.
    /// Matching those gave whole milk a density of 0.26 g/ml.
    private func density(label: String, grams: Double) -> Double? {
        let lowered = label.lowercased().trimmingCharacters(in: .whitespaces)

        // Split a leading quantity off the front, if there is one.
        let leading = lowered.prefix { $0.isNumber || $0 == "." || $0 == "/" || $0 == " " }
        let remainder = lowered.dropFirst(leading.count)

        // The unit has to start the remainder, not appear somewhere inside it.
        guard let unit = Self.volumeUnits.first(where: { remainder.hasPrefix($0.needle) }) else {
            return nil
        }
        let count = Self.parseQuantity(String(leading)) ?? 1
        guard count > 0 else { return nil }

        let density = grams / (unit.ml * count)
        // Foods range from about 0.3 (puffed cereal) to 1.6 (syrup, salt).
        // Anything outside that came from a mislabelled portion.
        guard density > 0.2, density < 2.0 else { return nil }
        return density
    }

    /// Parses "1", "1.5", or "1/2".
    static func parseQuantity(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                  denominator != 0
            else { return nil }
            return numerator / denominator
        }
        return Double(trimmed)
    }
}
