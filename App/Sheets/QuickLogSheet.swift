import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselIntelligence
import VesselIntents
import VesselNutrition

/// Type a meal the way you'd say it, and watch it become an entry.
///
/// The parse is shown *live and editable* rather than applied on save. That's
/// the whole design: a parser that fills things in silently is only pleasant
/// while it's right, and the moment it's wrong the user has logged something
/// they never ate without noticing. Showing the interpretation as it forms
/// makes being wrong cheap.
struct QuickLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var input = ""
    @State private var parsed: ParsedEntry?
    @State private var resolved: [EntryResolver.ResolvedFood] = []
    @State private var isParsing = false
    @State private var voiceError: String?
    /// Variant picked by hand, keyed by the resolved food it belongs to.
    @State private var variantChoices: [UUID: FoodRecord] = [:]
    @StateObject private var voice = VoiceTranscriber()
    @FocusState private var inputFocused: Bool

    private let pipeline = ParsePipeline()
    private let resolver = EntryResolver()
    private var writer: EntryWriter { EntryWriter(context: context, resolver: resolver) }

    /// Examples that double as instructions — faster to read than a tooltip,
    /// and tapping one shows what the parser does with it.
    private let examples = [
        "two eggs and toast",
        "a bowl of porridge with berries",
        "grilled chicken breast and rice",
        "glass of water",
        "feeling bloated after lunch"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: Layout.sm) {
                        TextField("What did you have?", text: $input, axis: .vertical)
                            .font(Typography.body)
                            .lineLimit(1...4)
                            .focused($inputFocused)
                            .accessibilityIdentifier("quickLogField")
                            .submitLabel(.done)

                        MicButton(isListening: voice.isListening) {
                            Task { await toggleVoice() }
                        }
                    }

                    if voice.isListening {
                        HStack(spacing: Layout.md) {
                            Waveform(level: voice.audioLevel, tint: Palette.diet)
                            Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                                .font(Typography.callout)
                                .foregroundStyle(voice.transcript.isEmpty ? Palette.inkTertiary : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Layout.xs)
                        .transition(.opacity)
                    }

                    if let voiceError {
                        Label(voiceError, systemImage: "exclamationmark.triangle")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.caution)
                    }
                } footer: {
                    Text("Say it however you'd say it out loud, or tap the microphone. Vessel works out the amounts.")
                }

                if let parsed, !input.isEmpty {
                    interpretation(parsed)
                    manualRoute
                } else if input.isEmpty {
                    // Straight under the field while it's empty, so it clears
                    // the keyboard; after a parse it follows the interpretation
                    // it's an alternative to.
                    manualRoute
                    Section("Try") {
                        ForEach(examples, id: \.self) { example in
                            Button {
                                input = example
                            } label: {
                                Text("“\(example)”")
                                    .font(Typography.callout)
                                    .foregroundStyle(Palette.diet)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .vesselSheetBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(Palette.diet)
        }
        .task(id: input) { await reparse() }
        .onChange(of: voice.transcript) { _, _ in handleVoiceChange() }
        .onChange(of: voice.state) { _, _ in handleVoiceChange() }
        .onDisappear { voice.cancel() }
        .onAppear { inputFocused = true }
    }

    // MARK: - Doing it by hand

    /// The way out when the parser isn't getting it.
    ///
    /// Always on screen, not only after a bad parse: someone who already
    /// knows the parser struggles with their phrasing shouldn't have to type a
    /// sentence first to be offered the form. It follows what was understood
    /// — a drink offers the drink form, a reaction the reaction form.
    private var manualRoute: some View {
        let destination: AppRouter.SheetDestination
        let title: String
        switch parsed?.intent {
        case .logWater:
            (destination, title) = (.logWater, "Log a drink yourself")
        case .logSymptom:
            (destination, title) = (.logSymptom, "Log a reaction yourself")
        default:
            (destination, title) = (.logFood, "Choose foods yourself")
        }

        return Section {
            Button {
                voice.cancel()
                // Swapping the presented sheet dismisses this one and opens the
                // form in its place, so there's never a sheet stacked on a sheet.
                router.present(destination)
            } label: {
                HStack(spacing: Layout.md) {
                    Image(systemName: "hand.point.up.left")
                        .font(.body)
                        .foregroundStyle(Palette.diet)
                        .frame(width: 28, height: 28)
                        .background(Palette.diet.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(Palette.ink)
                        Text("Not reading it right? Search and pick instead.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Spacer(minLength: Layout.xs)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickLogManualRoute")
        }
    }

    // MARK: - Interpretation

    @ViewBuilder
    private func interpretation(_ entry: ParsedEntry) -> some View {
        Section {
            HStack(spacing: Layout.sm) {
                Image(systemName: icon(for: entry.intent))
                    .foregroundStyle(tint(for: entry.intent))
                Text(description(for: entry.intent))
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Spacer()
                ConfidenceBadge(confidence: entry.confidence)
            }

            if let occurredAt = entry.occurredAt {
                LabeledContent("When") {
                    Text(occurredAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            if let slot = entry.slot {
                LabeledContent("Meal") {
                    Text(slot.title).foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            Text("Vessel read this as")
        }

        // Drinks are previewed where they will be saved: water in the Water
        // diary, anything else as food with its calories.
        let plans = entry.drinks.map { (drink: $0, plan: writer.plan(for: $0)) }
        let caloricDrinks = plans.filter { if case .food = $0.plan { return true } else { return false } }
        let waterDrinks = plans.filter { if case .water = $0.plan { return true } else { return false } }

        if !resolved.isEmpty || !caloricDrinks.isEmpty {
            Section("Foods") {
                ForEach(Array(resolved.enumerated()), id: \.element.id) { index, food in
                    ResolvedFoodRow(
                        resolved: food,
                        chosenVariant: variantChoices[food.id],
                        onChooseVariant: { variantChoices[food.id] = $0 },
                        onAddCompanion: { term in Task { await addCompanion(term) } }
                    )
                }
                ForEach(Array(caloricDrinks.enumerated()), id: \.offset) { _, item in
                    DrinkAsFoodRow(drink: item.drink, plan: item.plan)
                }
            }
        }

        if !waterDrinks.isEmpty {
            Section("Water") {
                ForEach(Array(waterDrinks.enumerated()), id: \.offset) { _, item in
                    LabeledContent(item.drink.name.capitalized) {
                        Text("\(Int(item.plan.millilitres)) ml")
                            .font(Typography.numeric)
                            .foregroundStyle(Palette.water)
                    }
                }
            }
        }

        if let symptom = entry.symptom {
            Section("Reaction") {
                LabeledContent(symptom.kind.title) {
                    Text(symptom.severity?.title ?? "Severity not given")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }

        if !entry.uncertainties.isEmpty {
            Section {
                ForEach(entry.uncertainties, id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
            } header: {
                Text("Worth checking")
            }
        }
    }

    // MARK: - Behaviour

    private var canSave: Bool {
        guard let parsed else { return false }
        return !parsed.isEmpty
    }

    private func reparse() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            parsed = nil
            resolved = []
            return
        }

        // Debounce so a fast typist doesn't trigger a database search per key.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        let pipeline = self.pipeline
        let resolver = self.resolver
        let result = await Task.detached(priority: .userInitiated) {
            let entry = pipeline.parse(text)
            return (entry, resolver.resolve(entry))
        }.value

        guard !Task.isCancelled else { return }
        withAnimation(Motion.quick) {
            parsed = result.0
            resolved = result.1
            // A fresh parse invalidates hand-picked variants: the foods it
            // refers to no longer exist.
            variantChoices = [:]
        }
    }

    /// Appends a suggested companion to what the user typed, so it goes back
    /// through the same parser rather than being bolted on afterwards.
    private func addCompanion(_ term: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = trimmed.isEmpty ? term : "\(trimmed) and \(term)"
    }

    /// Ids and names of the foods just saved, for pairing.
    // MARK: - Voice

    private func toggleVoice() async {
        voiceError = nil

        if voice.isListening {
            voice.stop()
            return
        }

        inputFocused = false
        await voice.start()

        if case .failed(let failure) = voice.state {
            voiceError = failure.message
        }
    }

    /// Mirrors speech into the text field as it arrives, so the parse updates
    /// while the user is still talking rather than only at the end.
    private func handleVoiceChange() {
        switch voice.state {
        case .listening:
            if !voice.transcript.isEmpty { input = voice.transcript }
        case .finished(let text):
            input = text
            voiceError = nil
        case .failed(let failure):
            voiceError = failure.message
        case .idle, .preparing:
            break
        }
    }

    private func save() {
        guard let parsed else { return }
        // The same writer Siri uses, so a sentence means the same thing
        // wherever it's said.
        EntryWriter(context: context).write(
            parsed,
            resolved: resolved,
            variantChoices: variantChoices,
            source: .text
        )
        Task { await StreakCoordinator.refresh(context: context) }
        dismiss()
    }

    // MARK: - Presentation

    private func icon(for intent: ParsedEntry.Intent) -> String {
        switch intent {
        case .logFood, .correction: return "fork.knife"
        case .logWater:             return "drop.fill"
        case .logSymptom:           return "stethoscope"
        case .journalEntry:         return "book.closed.fill"
        case .query, .unknown:      return "questionmark.circle"
        }
    }

    private func tint(for intent: ParsedEntry.Intent) -> Color {
        switch intent {
        case .logFood, .correction: return Palette.diet
        case .logWater:             return Palette.water
        case .logSymptom:           return Palette.symptom
        case .journalEntry:         return Palette.journal
        case .query, .unknown:      return Palette.inkTertiary
        }
    }

    private func description(for intent: ParsedEntry.Intent) -> String {
        switch intent {
        case .logFood:      return "A meal"
        case .logWater:     return "A drink"
        case .logSymptom:   return "A reaction"
        case .journalEntry: return "A journal note"
        case .correction:   return "A correction"
        case .query:        return "A question"
        case .unknown:      return "Not sure"
        }
    }
}

/// One resolved food, showing what it matched and how sure that is.
private struct ResolvedFoodRow: View {
    let resolved: EntryResolver.ResolvedFood
    let chosenVariant: FoodRecord?
    let onChooseVariant: (FoodRecord) -> Void
    let onAddCompanion: (String) -> Void

    private var food: FoodRecord? { chosenVariant ?? resolved.food }

    private var displayedNutrients: Nutrients {
        guard let food, let grams = resolved.grams else { return resolved.nutrients }
        return food.nutrients(forGrams: grams)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(food.map { FoodName($0.displayName).title } ?? resolved.phrase.capitalized)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Layout.xs)
                Text("\(Int(displayedNutrients.kilocalories)) kcal")
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.numericText(value: displayedNutrients.kilocalories))
            }

            HStack(spacing: Layout.xs) {
                Text("from “\(resolved.phrase)”")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                if let grams = resolved.grams {
                    Text("·")
                    Text("\(Int(grams)) g\(resolved.isEstimate ? " (est.)" : "")")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }

            if resolved.isUnmatched {
                // Said plainly rather than shown as a zero-calorie entry, which
                // would look like a successful parse of a calorie-free food.
                Label("No database match — saved with your wording and no nutrition.",
                      systemImage: "exclamationmark.triangle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.caution)
            }

            // "Milk" spans 34 to 61 kcal per 100 g. Picking one silently would
            // bury a difference big enough to matter, so it gets asked.
            if resolved.needsChoice {
                VStack(alignment: .leading, spacing: Layout.xs) {
                    Text("Which \(resolved.phrase.lowercased())?")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)

                    FlowLayout(spacing: Layout.xs) {
                        ForEach(resolved.variants) { variant in
                            let isChosen = (chosenVariant ?? resolved.food)?.id == variant.id
                            Button {
                                onChooseVariant(variant)
                            } label: {
                                Text(FoodVariants.distinguishingLabel(
                                    for: variant, term: resolved.phrase
                                ))
                                .font(Typography.captionEmphasis)
                                .foregroundStyle(isChosen ? .white : Palette.diet)
                                .padding(.horizontal, Layout.sm)
                                .padding(.vertical, 5)
                                .background(
                                    isChosen ? Palette.diet : Palette.diet.opacity(0.12),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, Layout.xs)
            }

            // Offered, never added: a suggestion you can ignore is helpful,
            // calories you didn't log are not.
            if let companion = resolved.suggestedCompanion {
                Button {
                    onAddCompanion(companion.searchTerm)
                } label: {
                    Label("Add \(companion.searchTerm)", systemImage: "plus.circle")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.diet)
                }
                .buttonStyle(.plain)
                .padding(.top, Layout.xs)
                .accessibilityHint(companion.note)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A compact confidence indicator.
private struct ConfidenceBadge: View {
    let confidence: Double

    private var label: String {
        switch confidence {
        case ..<0.5:  return "Unsure"
        case ..<0.72: return "Check it"
        default:      return "Confident"
        }
    }

    private var tint: Color {
        switch confidence {
        case ..<0.5:  return Palette.critical
        case ..<0.72: return Palette.caution
        default:      return Palette.positive
        }
    }

    var body: some View {
        Text(label)
            .font(Typography.captionEmphasis)
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.sm)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Parser confidence: \(label)")
    }
}


/// The microphone control.
///
/// Changes shape as well as colour when active, so the recording state survives
/// a screenshot, a colourblind viewer, and a glance.
private struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isListening ? Color.white : Palette.diet)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isListening ? Palette.diet : Palette.diet.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Stop listening" : "Dictate")
        .accessibilityIdentifier("quickLogMic")
    }
}


/// A drink that will be saved as food: its name, amount and energy.
private struct DrinkAsFoodRow: View {
    let drink: ParsedDrink
    let plan: EntryWriter.DrinkPlan

    private var record: FoodRecord? {
        if case .food(let record, _, _) = plan { return record }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.map { FoodName($0.displayName).title } ?? drink.name.capitalized)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Layout.xs)
                Text("\(Int(plan.kilocalories.rounded())) kcal")
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Text("from “\(drink.name)” · \(Int(plan.millilitres)) ml")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, 2)
    }
}
