import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// The day at a glance: streak, energy, macros, hydration, and what's been logged.
///
/// Ordered by what someone opening the app actually wants to know, in order:
/// am I on track, what have I eaten, what's left to do. Anything that isn't one
/// of those is a tap away rather than on this screen.
struct TodayScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Fetching the recent window rather than everything: the dashboard only ever
    // needs the last few days, and an unbounded fetch gets slower every week the
    // app is used.
    @Query private var recentFood: [FoodEntry]
    @Query private var recentWater: [WaterEntry]
    @Query private var profiles: [UserProfile]

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        _recentFood = Query(
            filter: #Predicate<FoodEntry> { $0.loggedAt >= cutoff },
            sort: \FoodEntry.loggedAt, order: .reverse
        )
        _recentWater = Query(
            filter: #Predicate<WaterEntry> { $0.loggedAt >= cutoff },
            sort: \WaterEntry.loggedAt, order: .reverse
        )
        _profiles = Query(sort: \UserProfile.createdAt)
    }

    private var profile: UserProfile? { profiles.first }
    private var plan: FastingPlan { profile?.fastingPlan ?? .standard }
    private var goals: DailyGoals { profile?.goals ?? .default }
    private var engine: StreakEngine { profile?.makeStreakEngine() ?? StreakEngine() }

    private var today: DayProgress {
        engine.progress(for: Date(), meals: recentFood, plan: plan)
    }

    private var streak: StreakState {
        engine.streak(
            qualifiedDays: engine.qualifiedDays(from: recentFood, plan: plan),
            allowedRestDays: profile?.allowedRestDaysPerWeek ?? 0
        )
    }

    private var todaysFood: [FoodEntry] {
        recentFood.filter { $0.loggedAt >= today.dayStart && $0.loggedAt < today.dayEnd }
    }

    private var todaysNutrients: Nutrients {
        Nutrients.sum(todaysFood.map(\.totalNutrients))
    }

    private var todaysWaterML: Double {
        let drunk = recentWater
            .filter { $0.loggedAt >= today.dayStart && $0.loggedAt < today.dayEnd }
            .reduce(0) { $0 + $1.volumeML }
        guard profile?.countsFoodWaterTowardHydration == true else { return drunk }
        return drunk + todaysNutrients.waterML
    }

    private var isAtRisk: Bool {
        engine.isAtRisk(
            progress: today,
            leadTime: profile?.streakWarningLeadTime ?? 4 * 3600
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.xl) {
                HStack(spacing: Layout.sm) {
                    QuickLogPrompt { router.present(.quickLog) }
                    CameraButton { router.present(.capture) }
                }

                StreakCard(
                    streak: streak,
                    progress: today,
                    plan: plan,
                    isAtRisk: isAtRisk
                )

                // Two columns on iPad, stacked on iPhone. The grid adapts rather
                // than the app shipping two hand-built layouts to keep in sync.
                LazyVGrid(columns: gridColumns, spacing: Layout.lg) {
                    EnergyCard(nutrients: todaysNutrients, goals: goals) {
                        router.present(.settings)
                    }
                    HydrationCard(
                        currentML: todaysWaterML,
                        goalML: goals.waterML,
                        onAdd: { router.present(.logWater) }
                    )
                }

                TodaysMealsCard(entries: todaysFood, plan: plan) {
                    router.present(.logFood)
                }

                if let profile, VesselCapabilities.current.canUpgrade, !profile.didDismissUpgradePrompt {
                    UpgradeCard {
                        profile.didDismissUpgradePrompt = true
                        try? context.save()
                    }
                }
            }
            .screenGutter()
            .padding(.top, Layout.lg)
            .padding(.bottom, Layout.xxxl + Layout.xl)
            .readableWidth(sizeClass == .compact ? .infinity : 900)
        }
        .background(Palette.ground)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        sizeClass == .compact
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Layout.lg), GridItem(.flexible())]
    }
}

// MARK: - Quick log

/// The app's front door: describe a meal in words.
///
/// Deliberately the first thing on the screen. Everything else here is a
/// readout of what's already logged; this is the one control that adds to it,
/// and burying it behind a tab would make the fastest path the least visible.
private struct QuickLogPrompt: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Layout.md) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundStyle(Palette.diet)
                Text("Describe a meal…")
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkTertiary)
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.diet.opacity(0.8))
            }
            .padding(.horizontal, Layout.lg)
            .padding(.vertical, Layout.md)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 0.5))
            .shadow(color: Color(hex: 0x3A2E20).opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick log")
        .accessibilityHint("Describe a meal in your own words")
        .accessibilityIdentifier("quickLogPrompt")
    }
}

/// Logging from a photo or a barcode.
private struct CameraButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "camera.fill")
                .font(.body)
                .foregroundStyle(Palette.diet)
                .frame(width: 48, height: 48)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.separator, lineWidth: 0.5))
                .shadow(color: Color(hex: 0x3A2E20).opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log from a photo")
        .accessibilityIdentifier("capturePrompt")
    }
}

// MARK: - Streak

private struct StreakCard: View {
    let streak: StreakState
    let progress: DayProgress
    let plan: FastingPlan
    let isAtRisk: Bool

    @Environment(AppRouter.self) private var router

    var body: some View {
        VesselCard(padding: Layout.lg) {
            VStack(alignment: .leading, spacing: Layout.lg) {
                HStack(alignment: .center, spacing: Layout.lg) {
                    ZStack {
                        StreakRing(
                            logged: progress.logged,
                            required: progress.required,
                            lineWidth: 12,
                            isAtRisk: isAtRisk
                        )

                        VStack(spacing: -2) {
                            if progress.isQualified {
                                // The day is done, so the streak count is the
                                // whole story.
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.positive)
                                    .padding(.bottom, 1)
                            }
                            Text("\(streak.current)")
                                .font(.system(size: 34, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(progress.isQualified ? Palette.positive : Palette.streak)
                                .contentTransition(.numericText())
                            Text(streak.current == 1 ? "day" : "days")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                    }
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: Layout.xs) {
                        Text(headline)
                            .font(Typography.heading)
                            .foregroundStyle(Palette.ink)

                        Text(detail)
                            .font(Typography.callout)
                            .foregroundStyle(isAtRisk ? Palette.streak : Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if streak.longest > streak.current, streak.longest > 0 {
                            Text("Best: \(streak.longest) days")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Divider().overlay(Palette.separator)

                // The meals themselves, named. The ring says how much of the
                // day is done; this says which part is missing.
                MealProgressRow(
                    meals: plan.qualifyingSlots.prefix(progress.required).map { slot in
                        MealProgressRow.Meal(
                            symbol: slot.symbol,
                            title: slot.title,
                            isLogged: progress.slotsLogged.contains(slot)
                        )
                    },
                    tint: progress.isQualified ? Palette.positive : Palette.streak
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(detail)")
    }

    private var headline: String {
        if progress.isQualified {
            return streak.current > 0 ? "\(streak.current)-day streak" : "Today is logged"
        }
        return isAtRisk ? "Streak at risk" : "Keep your streak"
    }

    private var detail: String {
        if progress.isQualified {
            return "You've logged today. Come back tomorrow to keep it going."
        }
        let remaining = progress.remaining
        let meals = remaining == 1 ? "1 more meal" : "\(remaining) more meals"

        if isAtRisk {
            let left = progress.timeRemaining()
            return "\(meals) in the next \(Self.durationText(left))."
        }
        return "\(meals) to go today."
    }

    /// "3 hours" / "45 minutes" — deliberately coarse, because a countdown ticking
    /// down to the second on a health app is stressful, not helpful.
    private static func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(max(1, minutes)) minutes"
        }
        let hours = minutes / 60
        return hours == 1 ? "hour" : "\(hours) hours"
    }
}

// MARK: - Energy

private struct EnergyCard: View {
    let nutrients: Nutrients
    let goals: DailyGoals
    let onSetGoals: () -> Void

    private var calorieFraction: Double {
        guard let goal = goals.kilocalories, goal > 0 else { return 0 }
        return nutrients.kilocalories / goal
    }

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.lg) {
                Text("Energy")
                    .font(Typography.heading)
                    .foregroundStyle(Palette.ink)

                HStack(alignment: .center, spacing: Layout.lg) {
                    // One ring, for one number. The macros get bars below, where
                    // they can be compared against each other honestly.
                    ZStack {
                        // With no calorie goal the ring has nothing to measure, so
                        // it becomes a plain container for the number rather than
                        // an arc stuck at zero.
                        if goals.kilocalories != nil {
                            ProgressRing(progress: calorieFraction, tint: Palette.diet, lineWidth: 11)
                        } else {
                            Circle().strokeBorder(Palette.diet.opacity(0.18), lineWidth: 11)
                        }
                        VStack(spacing: -1) {
                            Text(nutrients.kilocalories, format: .number.precision(.fractionLength(0)))
                                .font(Typography.metricSmall)
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("kcal")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                        .padding(Layout.md)
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: Layout.md) {
                        MacroBar(name: "Protein", value: nutrients.proteinG, goal: goals.proteinG, tint: Palette.protein)
                        MacroBar(name: "Carbs", value: nutrients.carbohydrateG, goal: goals.carbohydrateG, tint: Palette.carbs)
                        MacroBar(name: "Fat", value: nutrients.fatG, goal: goals.fatG, tint: Palette.fat)
                    }
                }

                if let goal = goals.kilocalories {
                    let remaining = goal - nutrients.kilocalories
                    Label(
                        remaining >= 0 ? "\(Int(remaining)) kcal remaining" : "\(Int(-remaining)) kcal over",
                        systemImage: remaining >= 0 ? "arrow.down.circle" : "exclamationmark.circle"
                    )
                    .font(Typography.caption)
                    .foregroundStyle(remaining >= 0 ? Palette.inkSecondary : Palette.caution)
                } else {
                    Button { onSetGoals() } label: {
                        Label("Set daily goals", systemImage: "target")
                            .font(Typography.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(Palette.diet)
                }
            }
        }
    }
}

// MARK: - Hydration

private struct HydrationCard: View {
    let currentML: Double
    let goalML: Double
    let onAdd: () -> Void

    private var progress: Double {
        goalML > 0 ? currentML / goalML : 0
    }

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.md) {
                Text("Hydration")
                    .font(Typography.heading)
                    .foregroundStyle(Palette.ink)

                HStack(alignment: .center, spacing: Layout.lg) {
                    LiquidFill(progress: progress, tint: Palette.water)
                        .clipShape(VesselShape())
                        .overlay(
                            VesselShape()
                                .stroke(Palette.water.opacity(0.35), lineWidth: 1.5)
                        )
                        .frame(width: 74, height: 104)

                    VStack(alignment: .leading, spacing: Layout.xs) {
                        MetricLabel(
                            value: currentML.formatted(.number.precision(.fractionLength(0))),
                            unit: "ml",
                            tint: Palette.water,
                            compact: true
                        )
                        Text("of \(Int(goalML)) ml goal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)

                        Button(action: onAdd) {
                            Label("Add water", systemImage: "plus")
                                .font(Typography.captionEmphasis)
                        }
                        .buttonStyle(.borderless)
                        .tint(Palette.water)
                        .padding(.top, Layout.xs)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Meals

private struct TodaysMealsCard: View {
    let entries: [FoodEntry]
    let plan: FastingPlan
    let onAdd: () -> Void

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.md) {
                SectionHeader("Today's meals") {
                    Button(action: onAdd) {
                        Label("Log", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                    .tint(Palette.diet)
                    .accessibilityLabel("Log food")
                }

                if entries.isEmpty {
                    Text("Nothing logged yet today.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.vertical, Layout.sm)
                } else {
                    ForEach(entries) { entry in
                        MealRow(entry: entry)
                        if entry.id != entries.last?.id {
                            Divider().overlay(Palette.separator)
                        }
                    }
                }
            }
        }
    }
}

private struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: Layout.md) {
            Image(systemName: entry.slot.symbol)
                .font(.body)
                .foregroundStyle(Palette.diet)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: Layout.xs) {
                    Text(entry.loggedAt, format: .dateTime.hour().minute())
                    Text("·")
                    Text(entry.slot.title)
                    if entry.needsReview {
                        Text("·")
                        Label("Check", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Palette.caution)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
            }

            Spacer(minLength: Layout.sm)

            Text("\(Int(entry.totalNutrients.kilocalories))")
                .font(Typography.numeric)
                .foregroundStyle(Palette.inkSecondary)
                + Text(" kcal")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Layout.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Upgrade prompt

/// Shown once on iOS 18, then only in Settings.
///
/// Framed as what's available rather than what's missing — the app on this OS is
/// complete, and nagging someone about a phone they may not be able to update
/// only breeds resentment.
private struct UpgradeCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.sm) {
                HStack {
                    Label(VesselCapabilities.upgradePromptTitle, systemImage: "sparkles")
                        .font(Typography.heading)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }

                Text(VesselCapabilities.upgradePromptMessage)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Layout.xs) {
                    ForEach(VesselCapabilities.upgradeBenefits, id: \.self) { benefit in
                        Label(benefit, systemImage: "checkmark.circle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(.top, Layout.xs)
            }
        }
    }
}

#Preview {
    NavigationStack { TodayScreen() }
        .environment(AppRouter())
        .modelContainer(VesselStore.previewContainer())
}
