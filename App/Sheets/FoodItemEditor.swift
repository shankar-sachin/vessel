import SwiftUI
import VesselCore
import VesselDesign

/// Adds or edits a single food within a meal.
///
/// Phase 1 is manual entry, so every number is typed. The layout is already
/// shaped for what comes next: when the food database and the parser land, the
/// name field becomes a search that fills the rest of this form in, and nothing
/// below it has to move.
struct FoodItemEditor: View {
    @Environment(\.dismiss) private var dismiss

    var existing: DraftFoodItem?
    let onCommit: (DraftFoodItem) -> Void

    @State private var draft: DraftFoodItem
    @State private var showsMacros = false
    @FocusState private var nameFocused: Bool

    init(existing: DraftFoodItem? = nil, onCommit: @escaping (DraftFoodItem) -> Void) {
        self.existing = existing
        self.onCommit = onCommit
        _draft = State(initialValue: existing ?? DraftFoodItem())
        // Open the macro fields straight away when they already hold values,
        // so editing doesn't hide data behind a disclosure.
        _showsMacros = State(initialValue: {
            guard let existing else { return false }
            return existing.proteinG > 0 || existing.carbohydrateG > 0 || existing.fatG > 0
        }())
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.quantity > 0
    }

    var body: some View {
        LogSheet(
            title: existing == nil ? "Add a food" : "Edit food",
            tint: Palette.diet,
            saveLabel: existing == nil ? "Add" : "Save",
            canSave: canSave,
            onSave: { onCommit(draft) }
        ) {
            Section {
                TextField("Food name", text: $draft.name)
                    .focused($nameFocused)
                    .accessibilityIdentifier("foodNameField")
                TextField("Brand (optional)", text: $draft.brand)
            } header: {
                Text("What")
            } footer: {
                Text("Searching a food database arrives in a later phase — for now these are your own numbers.")
            }

            Section("How much") {
                HStack {
                    TextField("Amount", value: $draft.quantity, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 90)
                    Picker("Unit", selection: $draft.unit) {
                        // Grouped so the long unit list stays scannable.
                        Section("Count") {
                            ForEach(countUnits, id: \.self) { Text($0.shortName).tag($0) }
                        }
                        Section("Weight") {
                            ForEach(massUnits, id: \.self) { Text($0.shortName).tag($0) }
                        }
                        Section("Volume") {
                            ForEach(volumeUnits, id: \.self) { Text($0.shortName).tag($0) }
                        }
                    }
                    .labelsHidden()
                }
            }

            Section {
                LabeledContent("Calories") {
                    HStack(spacing: Layout.xs) {
                        TextField("0", value: $draft.kilocalories.blankWhenZero, format: .number.precision(.fractionLength(0)))
                            .accessibilityIdentifier("foodCaloriesField")
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(Typography.numeric)
                            .frame(maxWidth: 80)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }

                Toggle("Add macros", isOn: $showsMacros.animation(Motion.quick))

                if showsMacros {
                    MacroField(label: "Protein", value: $draft.proteinG, tint: Palette.protein)
                    MacroField(label: "Carbohydrate", value: $draft.carbohydrateG, tint: Palette.carbs)
                    MacroField(label: "Fat", value: $draft.fatG, tint: Palette.fat)
                    MacroField(label: "Fiber", value: $draft.fiberG, tint: Palette.fiber)
                }
            } header: {
                Text("Nutrition")
            } footer: {
                // Catching a typo here is far cheaper than discovering it months
                // later when the correlation data looks strange.
                if draft.nutrients.hasImplausibleEnergy {
                    Label(
                        "These macros work out to about \(Int(draft.nutrients.derivedKilocalories)) kcal, which doesn't match the calories above.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(Palette.caution)
                }
            }

            Section("Ingredients") {
                TagEditor(
                    tags: $draft.tags,
                    tint: Palette.diet,
                    placeholder: "e.g. dairy, gluten"
                )
            }
        }
        .onAppear {
            if existing == nil { nameFocused = true }
        }
    }

    private var countUnits: [MeasurementUnit] { [.item, .slice, .serving, .handful, .pinch] }
    private var massUnits: [MeasurementUnit] { MeasurementUnit.allCases.filter(\.isMass) }
    private var volumeUnits: [MeasurementUnit] { MeasurementUnit.allCases.filter(\.isVolume) }
}

private struct MacroField: View {
    let label: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        LabeledContent {
            HStack(spacing: Layout.xs) {
                TextField("0", value: $value.blankWhenZero, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.numeric)
                    .frame(maxWidth: 80)
                Text("g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        } label: {
            HStack(spacing: Layout.sm) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
            }
        }
    }
}

/// Presents a numeric value of zero as an *empty* field rather than a literal
/// "0".
///
/// A field pre-filled with "0" means tapping it and typing "320" yields "3200",
/// because the caret lands before the existing zero. People hit this constantly
/// in nutrition apps and it produces entries that are wrong by an order of
/// magnitude while looking perfectly plausible. Showing a placeholder instead
/// makes the field behave the way it looks.
extension Binding where Value == Double {
    var blankWhenZero: Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue == 0 ? nil : wrappedValue },
            set: { wrappedValue = $0 ?? 0 }
        )
    }
}
