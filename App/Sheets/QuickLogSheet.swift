import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselIntelligence
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

    @State private var input = ""
    @State private var parsed: ParsedEntry?
    @State private var resolved: [EntryResolver.ResolvedFood] = []
    @State private var isParsing = false
    @State private var voiceError: String?
    @StateObject private var voice = VoiceTranscriber()
    @FocusState private var inputFocused: Bool

    private let pipeline = ParsePipeline()
    private let resolver = EntryResolver()

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
                } else if input.isEmpty {
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

        if !resolved.isEmpty {
            Section("Foods") {
                ForEach(resolved) { food in
                    ResolvedFoodRow(resolved: food)
                }
            }
        }

        if !entry.drinks.isEmpty {
            Section("Drinks") {
                ForEach(Array(entry.drinks.enumerated()), id: \.offset) { _, drink in
                    LabeledContent(drink.name.capitalized) {
                        Text(drink.millilitres.map { "\(Int($0)) ml" } ?? "—")
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
        }
    }

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

        switch parsed.intent {
        case .logFood, .correction:
            saveFood(parsed)
            // "toast and a coffee" is a meal that also names a drink.
            if !parsed.drinks.isEmpty { saveDrinks(parsed) }

        case .logWater:
            saveDrinks(parsed)
            // And the reverse: "a coffee and a biscuit" is mostly a drink, but
            // the biscuit still belongs in the food log.
            if !resolved.isEmpty { saveFood(parsed) }
        case .logSymptom:
            saveSymptom(parsed)
        case .journalEntry, .query, .unknown:
            saveJournal(parsed)
        }

        try? context.save()
        Task { await StreakCoordinator.refresh(context: context) }
        dismiss()
    }

    private func saveFood(_ parsed: ParsedEntry) {
        guard !resolved.isEmpty else { return }
        let entry = FoodEntry(
            loggedAt: parsed.occurredAt ?? Date(),
            slot: parsed.slot ?? MealSlot.inferred(from: parsed.occurredAt ?? Date()),
            source: .text,
            rawInput: parsed.original,
            parseConfidence: parsed.confidence
        )
        context.insert(entry)
        entry.items = resolved.map { food in
            let item = FoodItem(
                foodID: food.food?.id,
                displayName: food.food?.name ?? food.phrase.capitalized,
                quantity: food.quantity,
                unit: food.unit,
                grams: food.grams,
                nutrients: food.nutrients,
                tags: food.food?.tags ?? []
            )
            context.insert(item)
            return item
        }
    }

    private func saveDrinks(_ parsed: ParsedEntry) {
        for drink in parsed.drinks {
            context.insert(WaterEntry(
                loggedAt: parsed.occurredAt ?? Date(),
                volumeML: drink.millilitres ?? 250,
                source: .text,
                containerName: drink.name.capitalized,
                containsCaffeine: ["coffee", "tea", "espresso", "latte", "cola"]
                    .contains { drink.name.contains($0) }
            ))
        }
    }

    private func saveSymptom(_ parsed: ParsedEntry) {
        guard let symptom = parsed.symptom else { return }
        context.insert(SymptomEntry(
            occurredAt: parsed.occurredAt ?? Date(),
            kind: symptom.kind,
            severity: symptom.severity ?? .moderate,
            note: parsed.original
        ))
    }

    private func saveJournal(_ parsed: ParsedEntry) {
        context.insert(JournalEntry(body: parsed.original))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(resolved.food?.name ?? resolved.phrase.capitalized)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Layout.xs)
                Text("\(Int(resolved.nutrients.kilocalories)) kcal")
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.inkSecondary)
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
