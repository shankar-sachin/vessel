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
    @State private var lastPour: (ml: Double, token: Int)?
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
            .padding(.top, Layout.lg)
            .padding(.bottom, Layout.xxxl + Layout.xl)
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
                    splashToken: splashToken,
                    // The goal fills the body to the shoulder; the neck stays
                    // clear, as it would in a real carafe.
                    levelRange: 0.03...0.62
                )
                .clipShape(VesselShape())
                .background(VesselShape().fill(Palette.water.opacity(0.05)))
                .overlay(VesselGlass(tint: Palette.water))
                .frame(width: 150, height: 210)
                .overlay(alignment: .top) { pourLabel }

                VStack(spacing: Layout.xs) {
                    MetricLabel(
                        value: todayML.formatted(.number.precision(.fractionLength(0))),
                        unit: "ml",
                        tint: Palette.water
                    )
                    .contentTransition(.numericText(value: todayML))
                    // Standard, not fluid: an overshooting spring left digits
                    // half-rolled and blurred for most of a second.
                    .vesselAnimation(Motion.standard, value: todayML)
                    Text(statusText)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// One "+250 ml" at a time, rising out of the neck. A new pour replaces
    /// the last rather than stacking on it — stacked labels over the buttons
    /// were most of why adding water felt cluttered.
    @ViewBuilder
    private var pourLabel: some View {
        if let lastPour {
            Text("+\(Int(lastPour.ml)) ml")
                .font(Typography.captionEmphasis)
                .monospacedDigit()
                .foregroundStyle(Palette.water)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Palette.water.opacity(0.12), in: Capsule())
                .offset(y: -6)
                .id(lastPour.token)
                .transition(.asymmetric(
                    insertion: .offset(y: 14).combined(with: .opacity),
                    removal: .offset(y: -10).combined(with: .opacity)
                ))
                .task(id: lastPour.token) {
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(Motion.standard) { self.lastPour = nil }
                }
                .accessibilityHidden(true)
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
                                Text(entry.containerName ?? "Water")
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
        withAnimation(Motion.fluid) { lastPour = (ml, splashToken) }
    }

    private func delete(_ entry: WaterEntry) {
        context.delete(entry)
        try? context.save()
    }
}

