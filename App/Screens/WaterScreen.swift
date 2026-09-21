import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// The Water Diary. The liquid fill is the whole screen's centerpiece — it's the
/// one number people check most often, so it gets the most pleasant treatment.
struct WaterScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var entries: [WaterEntry]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    /// Incremented on every pour so the hero vessel knows to slosh. The value
    /// itself is meaningless — only the change matters.
    @State private var splashToken = 0
    @State private var editingEntry: WaterEntry?
    @State private var isAddingCustom = false

    private var profile: UserProfile? { profiles.first }
    private var engine: StreakEngine { profile?.makeStreakEngine() ?? StreakEngine() }
    private var goalML: Double { profile?.goals.waterML ?? 2000 }

    private var todaysEntries: [WaterEntry] {
        let start = engine.dayStart(for: Date())
        let end = engine.dayEnd(for: Date())
        return entries.filter { $0.loggedAt >= start && $0.loggedAt < end }
    }

    private var todayML: Double {
        todaysEntries.reduce(0) { $0 + $1.volumeML }
    }

    /// Common pours, sized to real containers rather than round numbers.
    private var quickAdds: [(label: String, ml: Double, symbol: String)] {
        profile?.unitSystem == .imperial
            ? [("Glass", 240, "cup.and.saucer"), ("Bottle", 500, "waterbottle"), ("Large", 750, "waterbottle.fill")]
            : [("Glass", 250, "cup.and.saucer"), ("Bottle", 500, "waterbottle"), ("Large", 750, "waterbottle.fill")]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.xl) {
                heroCard
                quickAddRow
                customAmountButton
                todaysDrinksCard
            }
            .screenGutter()
            .padding(.vertical, Layout.lg)
            .readableWidth(sizeClass == .compact ? .infinity : Layout.readableWidth)
        }
        .background(Palette.ground)
        .navigationTitle("Water Diary")
        .sheet(isPresented: $isAddingCustom) {
            LogWaterSheet()
        }
        .sheet(item: $editingEntry) { entry in
            LogWaterSheet(existing: entry)
        }
    }

    private var heroCard: some View {
        VesselCard(padding: Layout.xl) {
            VStack(spacing: Layout.lg) {
                LiquidFill(
                    progress: goalML > 0 ? todayML / goalML : 0,
                    tint: Palette.water,
                    splashToken: splashToken
                )
                .clipShape(VesselShape())
                .overlay(VesselShape().stroke(Palette.water.opacity(0.35), lineWidth: 2))
                .frame(width: 150, height: 210)

                VStack(spacing: Layout.xs) {
                    MetricLabel(
                        value: todayML.formatted(.number.precision(.fractionLength(0))),
                        unit: "ml",
                        tint: Palette.water
                    )
                    .contentTransition(.numericText(value: todayML))
                    .vesselAnimation(Motion.fluid, value: todayML)
                    Text(statusText)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusText: String {
        let remaining = goalML - todayML
        if remaining <= 0 { return "Goal reached — nicely done." }
        return "\(Int(remaining)) ml to go"
    }

    private var quickAddRow: some View {
        HStack(spacing: Layout.md) {
            ForEach(quickAdds, id: \.label) { item in
                QuickAddButton(
                    title: item.label,
                    detail: "\(Int(item.ml)) ml",
                    symbol: item.symbol,
                    burstText: "+\(Int(item.ml)) ml",
                    tint: Palette.water
                ) {
                    add(ml: item.ml, name: item.label)
                }
            }
        }
    }

    private var customAmountButton: some View {
        Button {
            isAddingCustom = true
        } label: {
            Label("Another amount", systemImage: "plus.circle")
                .font(Typography.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.water)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Layout.minTouchTarget)
    }

    private var todaysDrinksCard: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.md) {
                SectionHeader("Today")

                if todaysEntries.isEmpty {
                    Text("Nothing logged yet today.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    ForEach(todaysEntries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            HStack(spacing: Layout.md) {
                                Image(systemName: entry.containsCaffeine ? "cup.and.saucer.fill" : "drop.fill")
                                    .foregroundStyle(Palette.water)
                                    .frame(width: 22)
                                Text(entry.containerName ?? "Drink")
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(Int(entry.volumeML)) ml")
                                    .font(Typography.numeric)
                                    .foregroundStyle(Palette.inkSecondary)
                                Text(entry.loggedAt, format: .dateTime.hour().minute())
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.inkTertiary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
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
            }
        }
    }

    private func add(ml: Double, name: String) {
        let entry = WaterEntry(volumeML: ml, source: .quickAdd, containerName: name)
        context.insert(entry)
        try? context.save()
        // Tells the vessel to slosh. Haptics live in the button itself, so every
        // quick-add tile in the app feels identical.
        splashToken += 1
    }

    private func delete(_ entry: WaterEntry) {
        context.delete(entry)
        try? context.save()
    }
}

