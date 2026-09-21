import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Logs a meal: one eating occasion holding one or more foods.
///
/// Built around a *draft* rather than editing SwiftData objects directly.
/// Cancelling must leave nothing behind, and a half-built `FoodItem` inserted
/// into the context would already be in the user's history before they decided
/// to keep it. The draft is only committed on save.
struct LogFoodSheet: View {
    @Environment(\.modelContext) private var context

    var existing: FoodEntry?

    @State private var slot: MealSlot = MealSlot.inferred(from: Date())
    @State private var loggedAt: Date = Date()
    @State private var items: [DraftFoodItem] = []
    @State private var note: String = ""
    @State private var editingItem: DraftFoodItem?
    @State private var isAddingItem = false
    @State private var didLoad = false

    private var total: Nutrients {
        Nutrients.sum(items.map(\.nutrients))
    }

    var body: some View {
        LogSheet(
            title: existing == nil ? "Log food" : "Edit meal",
            tint: Palette.diet,
            canSave: !items.isEmpty,
            onSave: save
        ) {
            Section {
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker("Time", selection: $loggedAt, in: ...Date())
            }

            Section {
                if items.isEmpty {
                    Text("No foods yet.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            DraftItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                }

                Button {
                    isAddingItem = true
                } label: {
                    Label("Add a food", systemImage: "plus.circle.fill")
                        .foregroundStyle(Palette.diet)
                }
                .accessibilityIdentifier("addFoodButton")
            } header: {
                Text("Foods")
            } footer: {
                if !items.isEmpty {
                    Text("\(Int(total.kilocalories)) kcal · \(Int(total.proteinG))g protein · \(Int(total.carbohydrateG))g carbs · \(Int(total.fatG))g fat")
                        .font(Typography.numeric)
                }
            }

            Section("Notes") {
                TextField("Anything worth remembering", text: $note, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .sheet(isPresented: $isAddingItem) {
            FoodSearchSheet { newItem in
                items.append(newItem)
            }
        }
        .sheet(item: $editingItem) { item in
            FoodItemEditor(existing: item) { updated in
                guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
                items[index] = updated
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        slot = existing.slot
        loggedAt = existing.loggedAt
        note = existing.note ?? ""
        items = existing.resolvedItems.map(DraftFoodItem.init(from:))
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let entry: FoodEntry
        if let existing {
            entry = existing
            // Replace rather than reconcile: the item list is small, and
            // diffing it would be more code with more ways to go wrong.
            for item in entry.resolvedItems {
                context.delete(item)
            }
            entry.items = []
        } else {
            entry = FoodEntry(loggedAt: loggedAt, slot: slot, source: .manual)
            context.insert(entry)
        }

        entry.slot = slot
        entry.loggedAt = loggedAt
        entry.note = trimmedNote.isEmpty ? nil : trimmedNote
        // Typed by hand, so there's no parse to be unsure about.
        entry.parseConfidence = 1.0

        entry.items = items.map { draft in
            let item = draft.makeModel()
            context.insert(item)
            return item
        }

        try? context.save()

        // A new meal can complete the day's requirement, which has to reach the
        // Live Activity and the scheduled reminder.
        Task { await StreakCoordinator.refresh(context: context) }
    }
}

// MARK: - Draft model

/// An in-progress food item, held outside SwiftData until the meal is saved.
struct DraftFoodItem: Identifiable, Hashable {
    let id: UUID
    /// Database id when this came from a search, nil when typed by hand.
    var foodID: String?
    /// Resolved weight, when known. Kept so editing the quantity can rescale
    /// nutrition rather than leaving stale numbers behind.
    var grams: Double?
    var name: String
    var brand: String
    var quantity: Double
    var unit: MeasurementUnit
    var kilocalories: Double
    var proteinG: Double
    var carbohydrateG: Double
    var fatG: Double
    var fiberG: Double
    var tags: [String]

    init(
        id: UUID = UUID(),
        foodID: String? = nil,
        grams: Double? = nil,
        name: String = "",
        brand: String = "",
        quantity: Double = 1,
        unit: MeasurementUnit = .serving,
        kilocalories: Double = 0,
        proteinG: Double = 0,
        carbohydrateG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.foodID = foodID
        self.grams = grams
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.kilocalories = kilocalories
        self.proteinG = proteinG
        self.carbohydrateG = carbohydrateG
        self.fatG = fatG
        self.fiberG = fiberG
        self.tags = tags
    }

    init(from model: FoodItem) {
        let n = model.nutrients
        self.init(
            id: model.id,
            foodID: model.foodID,
            grams: model.grams,
            name: model.displayName,
            brand: model.brand ?? "",
            quantity: model.quantity,
            unit: model.unit,
            kilocalories: n.kilocalories,
            proteinG: n.proteinG,
            carbohydrateG: n.carbohydrateG,
            fatG: n.fatG,
            fiberG: n.fiberG,
            tags: model.resolvedTags
        )
    }

    var nutrients: Nutrients {
        Nutrients(
            kilocalories: kilocalories,
            proteinG: proteinG,
            carbohydrateG: carbohydrateG,
            fatG: fatG,
            fiberG: fiberG
        )
    }

    func makeModel() -> FoodItem {
        FoodItem(
            id: id,
            foodID: foodID,
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.isEmpty ? nil : brand,
            quantity: quantity,
            unit: unit,
            // Prefer the weight the resolver worked out; fall back to a direct
            // unit conversion for hand-typed items.
            grams: grams ?? unit.gramsPerUnit.map { $0 * quantity },
            nutrients: nutrients,
            tags: tags
        )
    }
}

private struct DraftItemRow: View {
    let item: DraftFoodItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit.shortName)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: Layout.xs)
            Text("\(Int(item.kilocalories)) kcal")
                .font(Typography.numeric)
                .foregroundStyle(Palette.inkSecondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Palette.inkTertiary)
        }
        .contentShape(Rectangle())
    }
}
