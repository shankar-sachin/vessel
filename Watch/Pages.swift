import SwiftUI
import VesselCore
import VesselDesign
import VesselIntelligence
import VesselNutrition

// MARK: - Today

/// The day at a glance: the streak ring, meals still needed, energy and water.
struct TodayPage: View {
    @Environment(WatchStore.self) private var store

    private var logged: Int { store.mealsLogged + store.pendingMeals }
    private var remaining: Int { max(0, store.mealsRequired - logged) }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    StreakRing(logged: logged, required: store.mealsRequired, lineWidth: 9)
                    VStack(spacing: -2) {
                        Text("\(store.streakDays)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(remaining == 0 ? Palette.positive : Palette.streak)
                        Text(store.streakDays == 1 ? "day" : "days")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.streakDays)-day streak, \(logged) of \(store.mealsRequired) meals today")

                Text(remaining == 0 ? "Today counts." : "\(remaining) more \(remaining == 1 ? "meal" : "meals") to go")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)

                HStack(spacing: 8) {
                    Stat(value: Int(store.kilocalories.rounded()).formatted(), unit: "kcal", tint: Palette.diet)
                    Stat(value: (store.waterML / 1000).formatted(.number.precision(.fractionLength(1))),
                         unit: "L water", tint: Palette.water)
                }

                Toggle("Meal reminders", isOn: $store.remindersEnabled)
                    .font(.footnote)
                    .tint(Palette.diet)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Vessel")
    }
}

private struct Stat: View {
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Water

/// The carafe, and a tap to fill it.
struct WaterPage: View {
    @Environment(WatchStore.self) private var store
    @State private var splash = 0

    var body: some View {
        VStack(spacing: 8) {
            LiquidFill(
                progress: store.waterGoalML > 0 ? store.waterML / store.waterGoalML : 0,
                tint: Palette.water,
                splashToken: splash,
                levelRange: 0.03...0.62
            )
            .clipShape(VesselShape())
            .background(VesselShape().fill(Palette.water.opacity(0.08)))
            .overlay(VesselGlass(tint: Palette.water))
            .frame(width: 58, height: 80)
            .accessibilityHidden(true)

            Text("\(Int(store.waterML)) ml")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.water)
                .contentTransition(.numericText(value: store.waterML))

            HStack(spacing: 6) {
                pour("Glass", 250)
                pour("Bottle", 500)
            }
        }
        .navigationTitle("Water")
    }

    private func pour(_ title: String, _ ml: Double) -> some View {
        Button {
            store.logWater(ml)
            splash += 1
            WKInterfaceDeviceHaptics.success()
        } label: {
            VStack(spacing: 0) {
                Text(title).font(.footnote.weight(.semibold))
                Text("\(Int(ml)) ml").font(.caption2).foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(Palette.water)
        .accessibilityLabel("Add a \(title.lowercased()), \(Int(ml)) millilitres")
    }
}

// MARK: - Log

/// Say it, see what Vessel understood, send it to the phone.
///
/// Parsed here with the same pipeline and database as the phone, so what's
/// shown is what will be saved; the phone does the saving.
struct LogPage: View {
    @Environment(WatchStore.self) private var store
    @State private var text = ""
    @State private var preview: Preview?
    @State private var sent = false

    struct Preview {
        let kind: String
        let lines: [String]
        let kilocalories: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("What did you have?", text: $text)
                    .onSubmit { read() }

                if let preview {
                    Text(preview.kind)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.diet)
                    ForEach(preview.lines, id: \.self) { line in
                        Text(line).font(.footnote)
                    }
                    if preview.kilocalories > 0 {
                        Text("\(preview.kilocalories) kcal")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Button("Log it") {
                        store.log(text)
                        WKInterfaceDeviceHaptics.success()
                        text = ""
                        self.preview = nil
                        sent = true
                    }
                    .tint(Palette.diet)
                }

                if sent && preview == nil {
                    Label("Sent to your phone", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.positive)
                }
            }
        }
        .navigationTitle("Log")
    }

    private func read() {
        sent = false
        let parsed = ParsePipeline().parse(text)
        guard !parsed.isEmpty || parsed.intent == .journalEntry else { preview = nil; return }
        let resolved = EntryResolver().resolve(parsed)
        let foods = resolved.map { $0.food.map { FoodName($0.displayName).title } ?? $0.phrase.capitalized }
        let drinks = parsed.drinks.map { $0.name.capitalized }
        let kind: String
        switch parsed.intent {
        case .logFood, .correction: kind = "A meal"
        case .logWater: kind = "A drink"
        case .logSymptom: kind = "A reaction"
        default: kind = "A journal note"
        }
        preview = Preview(
            kind: kind,
            lines: parsed.symptom.map { [$0.kind.title] } ?? (foods + drinks),
            kilocalories: Int(resolved.reduce(0) { $0 + $1.nutrients.kilocalories }.rounded())
        )
    }
}

/// The wrist's confirmation tap.
enum WKInterfaceDeviceHaptics {
    static func success() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

#if os(watchOS)
import WatchKit
#endif
