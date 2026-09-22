import SwiftUI
import VesselCore
import VesselDesign
import VesselNutrition

/// Asks how much of a chosen food was eaten, and shows the nutrition live.
///
/// The nutrition updates as the portion changes rather than appearing after
/// saving. Seeing 320 kcal turn into 640 when you switch from one cup to two is
/// what makes a portion choice feel considered instead of arbitrary.
struct FoodPortionSheet: View {

    let food: FoodRecord
    let onCommit: (DraftFoodItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Double = 1
    @State private var selectedPortion: FoodPortion?
    /// Set when measuring in a plain unit rather than one of the food's own.
    @State private var customUnit: MeasurementUnit?

    private let resolver = PortionResolver()

    /// Weight implied by the current choices.
    private var resolution: PortionResolver.Resolution? {
        if let portion = selectedPortion {
            return .init(grams: quantity * portion.grams, basis: .namedPortion(portion.label))
        }
        if let unit = customUnit {
            return resolver.grams(quantity: quantity, unit: unit, food: food)
        }
        return nil
    }

    private var grams: Double { resolution?.grams ?? 0 }
    private var nutrients: Nutrients { food.nutrients(forGrams: grams) }

    /// Plain units offered alongside the food's own measures.
    private let fallbackUnits: [MeasurementUnit] = [.gram, .ounce, .cup, .tablespoon, .fluidOunce]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let name = FoodName(food.displayName)
                    VStack(alignment: .leading, spacing: Layout.xs) {
                        Text(name.title)
                            .font(Typography.heading)
                            .foregroundStyle(Palette.ink)
                        if let detail = name.detail {
                            Text(detail)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                        if !food.tags.isEmpty {
                            FlowLayout(spacing: Layout.xs) {
                                ForEach(food.tags, id: \.self) { tag in
                                    VesselChip(tag, tint: Palette.diet)
                                }
                            }
                            .padding(.top, Layout.xs)
                        }
                    }
                    .padding(.vertical, Layout.xs)
                }

                Section("How much") {
                    Stepper(value: $quantity, in: 0.25...20, step: 0.25) {
                        LabeledContent("Amount") {
                            Text(quantity.formatted(.number.precision(.fractionLength(0...2))))
                                .font(Typography.numeric)
                                .foregroundStyle(Palette.ink)
                        }
                    }

                    Picker("Measured in", selection: measureBinding) {
                        if !food.portions.isEmpty {
                            Section("For this food") {
                                ForEach(food.portions) { portion in
                                    Text(portion.displayLabel).tag(Measure.portion(portion))
                                }
                            }
                        }
                        Section("Other") {
                            ForEach(fallbackUnits, id: \.self) { unit in
                                Text(unit.shortName).tag(Measure.unit(unit))
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Weight") {
                        Text("\(Int(grams.rounded())) g")
                            .font(Typography.numeric)
                            .foregroundStyle(Palette.ink)
                    }
                    macroRow("Calories", nutrients.kilocalories, "kcal", Palette.diet)
                    macroRow("Protein", nutrients.proteinG, "g", Palette.protein)
                    macroRow("Carbohydrate", nutrients.carbohydrateG, "g", Palette.carbs)
                    macroRow("Fat", nutrients.fatG, "g", Palette.fat)
                    macroRow("Fiber", nutrients.fiberG, "g", Palette.fiber)
                } header: {
                    Text("Nutrition")
                } footer: {
                    // Saying which conversions are measured and which are
                    // inferred, because a guess presented as a fact is how a
                    // food log quietly stops being trustworthy.
                    if let resolution, resolution.isEstimate {
                        Label(estimateExplanation(resolution), systemImage: "info.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .vesselSheetBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commit() }
                        .fontWeight(.semibold)
                        .disabled(grams <= 0)
                }
            }
            .tint(Palette.diet)
        }
        .onAppear {
            // Open on the food's own default measure — people think in cups and
            // slices, not grams.
            if let portion = food.defaultPortion {
                selectedPortion = portion
            } else {
                customUnit = .gram
                quantity = 100
            }
        }
    }

    private func macroRow(_ label: String, _ value: Double, _ unit: String, _ tint: Color) -> some View {
        LabeledContent {
            // Energy reads as a whole number everywhere else in the app;
            // "203.8 kcal" suggests a precision the database doesn't have.
            Text("\(value.formatted(.number.precision(.fractionLength(unit == "kcal" ? 0...0 : 0...1)))) \(unit)")
                .font(Typography.numeric)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: value))
        } label: {
            HStack(spacing: Layout.sm) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
            }
        }
        .vesselAnimation(Motion.quick, value: value)
    }

    private func estimateExplanation(_ resolution: PortionResolver.Resolution) -> String {
        switch resolution.basis {
        case .density:
            return "Converted from volume using this food's measured density, so the weight is approximate."
        case .assumption:
            return "Vessel doesn't have measurements for this food, so the weight is a rough estimate. Adjust it if you know better."
        case .defaultServing(let label):
            return "Based on a typical serving of \(label)."
        case .weight, .namedPortion:
            return ""
        }
    }

    // MARK: - Measure selection

    /// One picker over two kinds of measure.
    private enum Measure: Hashable {
        case portion(FoodPortion)
        case unit(MeasurementUnit)
    }

    private var measureBinding: Binding<Measure> {
        Binding(
            get: {
                if let selectedPortion { return .portion(selectedPortion) }
                return .unit(customUnit ?? .gram)
            },
            set: { measure in
                switch measure {
                case .portion(let portion):
                    selectedPortion = portion
                    customUnit = nil
                case .unit(let unit):
                    selectedPortion = nil
                    customUnit = unit
                    // Switching to grams from "1 cup" should not leave the
                    // amount at 1, which would read as one gram.
                    if unit == .gram, quantity < 5 { quantity = 100 }
                    if unit != .gram, quantity > 20 { quantity = 1 }
                }
            }
        )
    }

    private func commit() {
        let unit: MeasurementUnit
        if selectedPortion != nil {
            unit = .serving
        } else {
            unit = customUnit ?? .gram
        }

        onCommit(DraftFoodItem(
            foodID: food.id,
            grams: grams,
            name: food.displayName,
            brand: "",
            quantity: quantity,
            unit: unit,
            kilocalories: nutrients.kilocalories,
            proteinG: nutrients.proteinG,
            carbohydrateG: nutrients.carbohydrateG,
            fatG: nutrients.fatG,
            fiberG: nutrients.fiberG,
            tags: food.tags
        ))
        dismiss()
    }
}
