import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Settings, with the streak and fasting rules front and centre — they're the
/// thing most worth tuning to how someone actually eats.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    /// Set when the user asked for reminders but iOS has them switched off, so
    /// we can explain rather than leaving a toggle that silently flips back.
    @State private var notificationsBlocked = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile {
                    streakSection(profile)
                    goalsSection(profile)
                    unitsSection(profile)
                }
                DataSettingsSection()
                capabilitySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
    }

    // MARK: Streak

    @ViewBuilder
    private func streakSection(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile

        Section {
            NavigationLink {
                FastingPlanPicker(profile: profile)
            } label: {
                LabeledContent("Eating pattern") {
                    Text(profile.fastingPlan.style.title)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            LabeledContent("Meals to keep a streak") {
                Text("\(profile.fastingPlan.mealsRequired)")
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Picker("Day resets at", selection: $profile.dayRolloverHour) {
                ForEach(rolloverChoices, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }

            Stepper(value: $profile.allowedRestDaysPerWeek, in: 0...3) {
                LabeledContent("Rest days allowed") {
                    Text(profile.allowedRestDaysPerWeek == 0
                         ? "None"
                         : "\(profile.allowedRestDaysPerWeek) a week")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            Text("Streak")
        } footer: {
            Text(profile.allowedRestDaysPerWeek == 0
                 ? "Your streak breaks if you miss a day."
                 : "You can miss up to \(profile.allowedRestDaysPerWeek) day\(profile.allowedRestDaysPerWeek == 1 ? "" : "s") a week without losing your streak.")
        }

        Section {
            Toggle("Countdown in Dynamic Island", isOn: $profile.liveActivityEnabled)
            Toggle("Remind me before the day ends", isOn: $profile.streakReminderEnabled)
                .onChange(of: profile.streakReminderEnabled) { _, isOn in
                    guard isOn else { return }
                    // Ask at the moment the intent is expressed, so the system
                    // dialog has visible context behind it.
                    Task {
                        let granted = await StreakReminderScheduler.requestAuthorization()
                        if !granted {
                            profile.streakReminderEnabled = false
                            notificationsBlocked = true
                        }
                        try? context.save()
                    }
                }

            if profile.liveActivityEnabled || profile.streakReminderEnabled {
                Picker("Start warning", selection: $profile.streakWarningLeadHours) {
                    ForEach([2.0, 3.0, 4.0, 6.0], id: \.self) { hours in
                        Text("\(Int(hours)) hours before").tag(hours)
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            VStack(alignment: .leading, spacing: Layout.xs) {
                if notificationsBlocked {
                    Label(
                        "Notifications are turned off for Vessel in iOS Settings.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(Palette.caution)
                }
                // Being straight about the mechanism, because a Live Activity that
                // sometimes doesn't appear looks like a bug unless you know why.
                Text("The notification is guaranteed. The Dynamic Island countdown starts when iOS next gives Vessel a moment to run, which is usually but not always on time.")
            }
        }
    }

    private var rolloverChoices: [Int] { [0, 1, 2, 3, 4, 5] }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "Midnight" }
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Goals

    @ViewBuilder
    private func goalsSection(_ profile: UserProfile) -> some View {
        Section("Daily goals") {
            GoalRow(title: "Energy", unit: "kcal",
                    value: Binding(get: { profile.goals.kilocalories }, set: { profile.goals.kilocalories = $0 }))
            GoalRow(title: "Protein", unit: "g",
                    value: Binding(get: { profile.goals.proteinG }, set: { profile.goals.proteinG = $0 }))
            GoalRow(title: "Carbohydrate", unit: "g",
                    value: Binding(get: { profile.goals.carbohydrateG }, set: { profile.goals.carbohydrateG = $0 }))
            GoalRow(title: "Fat", unit: "g",
                    value: Binding(get: { profile.goals.fatG }, set: { profile.goals.fatG = $0 }))
            GoalRow(title: "Water", unit: "ml",
                    value: Binding(get: { profile.goals.waterML }, set: { profile.goals.waterML = $0 ?? 2000 }))
        }
    }

    @ViewBuilder
    private func unitsSection(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile

        Section("Units") {
            Picker("Measurements", selection: $profile.unitSystem) {
                ForEach(UnitSystem.allCases, id: \.self) { system in
                    Text(system.title).tag(system)
                }
            }
            Toggle("Count water in food", isOn: $profile.countsFoodWaterTowardHydration)
        }
    }

    // MARK: Capability

    @ViewBuilder
    private var capabilitySection: some View {
        if VesselCapabilities.current.canUpgrade {
            Section {
                VStack(alignment: .leading, spacing: Layout.sm) {
                    Text(VesselCapabilities.upgradePromptMessage)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(VesselCapabilities.upgradeBenefits, id: \.self) { benefit in
                        Label(benefit, systemImage: "checkmark.circle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(.vertical, Layout.xs)
            } header: {
                Text(VesselCapabilities.upgradePromptTitle)
            } footer: {
                Text("Everything else in Vessel already works on this version.")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.appVersionDisplay)
            LabeledContent("Data", value: "Stored on this device")
        } header: {
            Text("About")
        } footer: {
            Text("Vessel keeps your log on your device. Nothing is sent anywhere except the backup folder you choose.")
        }
    }

    private func save() {
        try? context.save()
    }
}

private struct GoalRow: View {
    let title: String
    let unit: String
    @Binding var value: Double?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Layout.xs) {
                TextField(
                    "Not set",
                    value: $value,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(Typography.numeric)
                .frame(maxWidth: 90)

                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

/// Picks the eating pattern, and explains what each one asks of you.
private struct FastingPlanPicker: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Form {
            Section {
                ForEach(FastingPlan.presets) { preset in
                    Button {
                        profile.fastingPlan = preset
                    } label: {
                        HStack(alignment: .top, spacing: Layout.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.style == .timeRestricted
                                     ? "\(preset.style.title) (\(preset.windowDescription ?? ""))"
                                     : preset.style.title)
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.ink)
                                Text(preset.style.detail)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.inkTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if isSelected(preset) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.streak)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Pattern")
            } footer: {
                Text("Pick what matches how you actually eat. The streak follows your pattern rather than the other way around.")
            }

            Section("Fine-tuning") {
                Stepper(value: mealsBinding, in: 1...6) {
                    LabeledContent("Meals required") {
                        Text("\(profile.fastingPlan.mealsRequired)")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Toggle("Snacks count as a meal", isOn: snacksBinding)
            }
        }
        .navigationTitle("Eating pattern")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ preset: FastingPlan) -> Bool {
        profile.fastingPlan.style == preset.style
    }

    // The plan is stored encoded, so each tweak reads, mutates and writes back
    // the whole value rather than binding into it directly.
    private var mealsBinding: Binding<Int> {
        Binding(
            get: { profile.fastingPlan.mealsRequired },
            set: { newValue in
                var plan = profile.fastingPlan
                plan.mealsRequired = newValue
                // Any manual change means it's no longer a stock preset.
                if plan.style != .timeRestricted { plan.style = .custom }
                profile.fastingPlan = plan
            }
        )
    }

    private var snacksBinding: Binding<Bool> {
        Binding(
            get: { profile.fastingPlan.countsSnacks },
            set: { newValue in
                var plan = profile.fastingPlan
                plan.countsSnacks = newValue
                profile.fastingPlan = plan
            }
        )
    }
}

extension Bundle {
    var appVersionDisplay: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
