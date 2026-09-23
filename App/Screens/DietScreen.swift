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

    /// True while a photo is being dragged over the log.
    @State private var isDropTargeted = false

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
        // On iPad, drag a photo from Photos or Files straight onto the log to
        // read the food in it — the same capture flow as the camera button.
        .dropDestination(for: Data.self) { items, _ in
            guard let data = items.first, UIImage(data: data) != nil else { return false }
            router.present(.captureImage(data))
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Layout.radiusLarge, style: .continuous)
                    .strokeBorder(Palette.diet, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Palette.diet.opacity(0.06), in: RoundedRectangle(cornerRadius: Layout.radiusLarge, style: .continuous))
                    .overlay(Label("Drop a photo to read the food", systemImage: "photo.badge.plus")
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.diet))
                    .padding(Layout.md)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .vesselAnimation(Motion.quick, value: isDropTargeted)
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
        AdaptiveStack(alignment: .firstTextBaseline) {
            Text(relativeTitle)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
            AdaptiveSpacer()
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
                AdaptiveStack(spacing: Layout.sm) {
                    Label(entry.slot.title, systemImage: entry.slot.symbol)
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(Palette.diet)
                    Text(entry.loggedAt, format: .dateTime.hour().minute())
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                    AdaptiveSpacer()
                    // A meal's total, when there is more than one line to add up.
                    if entry.resolvedItems.count > 1 {
                        Text("\(Int(entry.resolvedItems.reduce(0) { $0 + $1.nutrients.kilocalories }.rounded())) kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }

                ForEach(entry.resolvedItems) { item in
                    let name = FoodName(item.displayName)
                    AdaptiveStack(alignment: .firstTextBaseline, spacing: Layout.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.title)
                                .font(Typography.body)
                                .foregroundStyle(Palette.ink)
                            Text([name.detail, item.quantityDescription].compactMap { $0 }.joined(separator: " · "))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                        }
                        AdaptiveSpacer(minLength: Layout.sm)
                        Text("\(Int(item.nutrients.kilocalories.rounded())) kcal")
                            .font(Typography.numeric)
                            .foregroundStyle(Palette.inkSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }

                // The verbatim input, shown when we parsed rather than were told —
                // it's how the user checks our work without opening an editor.
                if let raw = entry.rawInput, !raw.isEmpty {
                    // Never cut short: it's what the person said, and at large
                    // text sizes a two-line cap clipped it mid-sentence.
                    Text("“\(raw)”")
                        .font(Typography.caption)
                        .italic()
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
