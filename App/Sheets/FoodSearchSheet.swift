import SwiftUI
import VesselCore
import VesselDesign
import VesselNutrition

/// Finds a food in the bundled database, then asks how much of it.
///
/// Search first, typing second. Before Phase 2 every number was entered by
/// hand, which is accurate but slow enough that people stop doing it. Manual
/// entry is still one tap away for anything the database doesn't know.
struct FoodSearchSheet: View {

    let onCommit: (DraftFoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [FoodMatch] = []
    @State private var selected: FoodRecord?
    @State private var isEnteringManually = false
    /// Guards against an older search overwriting a newer one, which otherwise
    /// makes results flicker backwards as you type quickly.
    @State private var searchGeneration = 0

    private let search = FoodSearch()

    var body: some View {
        NavigationStack {
            Group {
                if !FoodDatabase.shared.isAvailable {
                    unavailableState
                } else {
                    resultsList
                }
            }
            .background(Palette.ground)
            .navigationTitle("Add a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Manual") { isEnteringManually = true }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search foods"
            )
            .tint(Palette.diet)
        }
        .navigationDestinationForPortion(selected: $selected, onCommit: commit)
        .sheet(isPresented: $isEnteringManually) {
            FoodItemEditor { item in
                onCommit(item)
                dismiss()
            }
        }
        .task(id: query) { await runSearch() }
        .onAppear { if matches.isEmpty { matches = search.suggestions() } }
    }

    // MARK: - Content

    private var resultsList: some View {
        List {
            if query.isEmpty {
                Section("Common foods") {
                    ForEach(matches) { match in
                        row(for: match)
                    }
                }
            } else if matches.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: Layout.sm) {
                        Text("Nothing matched “\(query)”.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.ink)
                        Text("The database covers generic foods rather than brands. You can enter this one yourself.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                        Button("Enter it manually") { isEnteringManually = true }
                            .buttonStyle(.borderless)
                            .tint(Palette.diet)
                            .padding(.top, Layout.xs)
                    }
                    .padding(.vertical, Layout.sm)
                }
            } else {
                Section {
                    ForEach(matches) { match in
                        row(for: match)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(for match: FoodMatch) -> some View {
        Button {
            selected = match.food
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Layout.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.food.name)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Layout.xs) {
                        Text("\(Int(match.food.nutrientsPer100g.kilocalories)) kcal / 100 g")
                        if let portion = match.food.defaultPortion {
                            Text("·")
                            Text(portion.label)
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)

                    if !match.food.tags.isEmpty {
                        // Showing tags here rather than only in the detail view
                        // means someone avoiding dairy can see it before tapping.
                        Text(match.food.tags.prefix(3).joined(separator: " · "))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.diet.opacity(0.85))
                    }
                }
                Spacer(minLength: Layout.xs)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var unavailableState: some View {
        EmptyStateView(
            icon: "exclamationmark.icloud",
            title: "Food database unavailable",
            message: "Vessel couldn't open its food database. You can still add foods by entering the numbers yourself.",
            tint: Palette.diet
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Behaviour

    private func runSearch() async {
        searchGeneration += 1
        let generation = searchGeneration

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            matches = search.suggestions()
            return
        }

        // Debounce: searching on literally every keystroke wastes work while
        // someone is mid-word, and 150ms is below the threshold where typing
        // starts to feel laggy.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, generation == searchGeneration else { return }

        let query = self.query
        let results = await Task.detached(priority: .userInitiated) { [search] in
            search.search(query)
        }.value

        guard generation == searchGeneration else { return }
        matches = results
    }

    private func commit(_ item: DraftFoodItem) {
        onCommit(item)
        dismiss()
    }
}

private extension View {
    /// Pushes the portion picker when a food is chosen.
    func navigationDestinationForPortion(
        selected: Binding<FoodRecord?>,
        onCommit: @escaping (DraftFoodItem) -> Void
    ) -> some View {
        sheet(item: selected) { food in
            FoodPortionSheet(food: food, onCommit: onCommit)
        }
    }
}
