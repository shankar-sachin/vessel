import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// The food log, grouped by day.
struct DietScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var entries: [FoodEntry]

    /// The meal being edited, if any.
    @State private var editingEntry: FoodEntry?
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var engine: StreakEngine {
        profiles.first?.makeStreakEngine() ?? StreakEngine()
    }

    /// Grouped by streak day rather than calendar day, so a late-night meal
    /// appears under the day the user considers it part of.
    private var grouped: [(day: Date, entries: [FoodEntry])] {
        Dictionary(grouping: entries) { engine.dayStart(for: $0.loggedAt) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.loggedAt > $1.loggedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    icon: "fork.knife",
                    title: "No meals logged",
                    message: "Tell Vessel what you ate — speak it, photograph it, or type it.",
                    tint: Palette.diet
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Layout.xl, pinnedViews: .sectionHeaders) {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                VStack(spacing: Layout.md) {
                                    ForEach(group.entries) { entry in
                                        Button {
                                            editingEntry = entry
                                        } label: {
                                            FoodEntryCard(entry: entry)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                editingEntry = entry
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                delete(entry)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            } header: {
                                DayHeader(date: group.day, calories: totalCalories(group.entries))
                            }
                        }
                    }
                    .screenGutter()
                    .padding(.top, Layout.lg)
                    .padding(.bottom, Layout.xxxl + Layout.xl)
                    .readableWidth(sizeClass == .compact ? .infinity : Layout.readableWidth)
                }
            }
        }
        .background(Palette.ground)
        .navigationTitle("Diet Tracker")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.present(.logFood) } label: {
                    Label("Log food", systemImage: "plus")
                }
                .tint(Palette.diet)
            }
        }
        .sheet(item: $editingEntry) { entry in
            LogFoodSheet(existing: entry)
        }
    }

    private func delete(_ entry: FoodEntry) {
        context.delete(entry)
        try? context.save()
        // Removing a meal can break today's streak, so both reminder surfaces
        // need to hear about it.
        Task { await StreakCoordinator.refresh(context: context) }
    }

    private func totalCalories(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.totalNutrients.kilocalories }
    }
}

/// Sticky day header with that day's total.
struct DayHeader: View {
    let date: Date
    let calories: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(relativeTitle)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("\(Int(calories)) kcal")
                .font(Typography.numeric)
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Layout.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ground)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Today" and "Yesterday" read faster than a date, and those are the two
    /// days people look at most.
    private var relativeTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct FoodEntryCard: View {
    let entry: FoodEntry

    var body: some View {
        VesselCard(padding: Layout.md) {
            VStack(alignment: .leading, spacing: Layout.sm) {
                HStack(spacing: Layout.sm) {
                    Label(entry.slot.title, systemImage: entry.slot.symbol)
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(Palette.diet)
                    Text(entry.loggedAt, format: .dateTime.hour().minute())
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                    Spacer()
                    Image(systemName: entry.source.symbol)
                        .font(.caption)
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                }

                ForEach(entry.resolvedItems) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Layout.sm) {
                        Text(item.displayName)
                            .font(Typography.body)
                            .foregroundStyle(Palette.ink)
                        Text(item.quantityDescription)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                        Spacer(minLength: Layout.xs)
                        Text("\(Int(item.nutrients.kilocalories)) kcal")
                            .font(Typography.numeric)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                // The verbatim input, shown when we parsed rather than were told —
                // it's how the user checks our work without opening an editor.
                if let raw = entry.rawInput, !raw.isEmpty {
                    Text("“\(raw)”")
                        .font(Typography.caption)
                        .italic()
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(2)
                }

                if entry.needsReview {
                    Label("Worth checking — we weren't confident about this one",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.caution)
                }
            }
        }
    }
}
