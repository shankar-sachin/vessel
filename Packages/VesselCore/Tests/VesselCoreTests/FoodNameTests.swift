import Testing
@testable import VesselCore

@Suite("Food names read the way people say them")
struct FoodNameTests {

    @Test("A kind moves in front of the food; states become detail")
    func kindsAndStates() {
        #expect(FoodName("Rice, white, cooked, no added fat") == .init(title: "White rice", detail: "cooked · no added fat"))
        #expect(FoodName("Milk, whole") == .init(title: "Whole milk", detail: nil))
        #expect(FoodName("Cheese, Cheddar") == .init(title: "Cheddar cheese", detail: nil))
        #expect(FoodName("Egg, whole, raw") == .init(title: "Whole egg", detail: "raw"))
        #expect(FoodName("Coffee, brewed") == .init(title: "Coffee", detail: "brewed"))
        #expect(FoodName("Banana, raw") == .init(title: "Banana", detail: "raw"))
        #expect(FoodName("Melon, frozen") == .init(title: "Melon", detail: "frozen"))
    }

    @Test("A plural second clause is the food itself")
    func pluralIsTheFood() {
        #expect(FoodName("Nuts, almonds").title == "Almonds")
    }

    @Test("Names already in speaking order are left alone")
    func alreadyNatural() {
        #expect(FoodName("Porridge with berries") == .init(title: "Porridge with berries", detail: nil))
        #expect(FoodName("Melba toast").title == "Melba toast")
        #expect(FoodName("Chicken breast, grilled") == .init(title: "Chicken breast", detail: "grilled"))
    }

    @Test("USDA's not-specified clauses never reach the screen")
    func unspecifiedDropped() {
        #expect(FoodName("Chicken, NS as to part and cooking method, NS as to skin eaten")
                == .init(title: "Chicken", detail: nil))
    }

    @Test("Units pluralise where English does")
    func plurals() {
        #expect(MeasurementUnit.serving.shortName(for: 2) == "servings")
        #expect(MeasurementUnit.serving.shortName(for: 1) == "serving")
        #expect(MeasurementUnit.gram.shortName(for: 150) == "g")
    }
}
