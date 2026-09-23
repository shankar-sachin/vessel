import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Logs a reaction for the Date Log.
///
/// The one field that matters most here is **when it happened**, not when it was
/// typed. The correlation engine measures backwards from onset, so a symptom
/// recorded at bedtime but felt at 3pm is worthless if we store the wrong time.
/// That's why the time picker is prominent and pre-filled with quick offsets
/// rather than buried.
struct LogSymptomSheet: View {
    @Environment(\.modelContext) private var context

    var existing: SymptomEntry?

    @State private var kind: SymptomKind = .bloating
    @State private var severity: Severity = .moderate
    @State private var occurredAt: Date = Date()
    @State private var durationMinutes: Int = 60
    @State private var hasDuration = false
    @State private var note: String = ""
    @State private var didLoad = false
    /// Non-digestive categories start collapsed — see `visibleGroups`.
    @State private var showsAllCategories = false

    /// Symptoms grouped the way the picker presents them.
    private var grouped: [(category: String, kinds: [SymptomKind])] {
        let order = ["Digestive", "Systemic", "Allergic", "Other"]
        return order.compactMap { category in
            let kinds = SymptomKind.allCases.filter { $0.category == category }
            return kinds.isEmpty ? nil : (category, kinds)
        }
    }

    /// Only the digestive group until the user asks for more.
    ///
    /// All sixteen chips at once pushed severity and — worse — the *time* field
    /// off the bottom of the sheet, and time is the field this whole feature
    /// depends on being right. Vessel's Date Log is about reactions to food, so
    /// digestive symptoms are the overwhelmingly common case and get to be the
    /// default; everything else is one tap away.
    private var visibleGroups: [(category: String, kinds: [SymptomKind])] {
        showsAllCategories ? grouped : grouped.filter { $0.category == "Digestive" }
    }

    /// Three across on a phone, more where there's room. A grid rather than a
    /// flow of pills: equal tiles scan as a set of choices, where ragged pills
    /// read as a paragraph — and a flow layout nested in a Form row is exactly
    /// what once rendered every chip as a tall, empty capsule.
    private let tileColumns = [GridItem(.adaptive(minimum: 96), spacing: Layout.sm)]

    var body: some View {
        LogSheet(
            title: existing == nil ? "Log a reaction" : "Edit reaction",
            tint: Palette.symptom,
            canSave: true,
            onSave: save
        ) {
            Section {
                VStack(alignment: .leading, spacing: Layout.md) {
                    ForEach(visibleGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: Layout.sm) {
                            // The group name only earns its place once there
                            // is more than one group on screen.
                            if showsAllCategories {
                                Text(group.category)
                                    .font(Typography.captionEmphasis)
                                    .foregroundStyle(Palette.inkTertiary)
                                    .textCase(.uppercase)
                            }
                            LazyVGrid(columns: tileColumns, spacing: Layout.sm) {
                                ForEach(group.kinds) { candidate in
                                    SymptomTile(kind: candidate, isSelected: kind == candidate) {
                                        kind = candidate
                                    }
                                }
                            }
                        }
                    }

                    if !showsAllCategories {
                        Button {
                            withAnimation(Motion.standard) { showsAllCategories = true }
                        } label: {
                            HStack(spacing: Layout.xs) {
                                Text("More symptoms")
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                            .font(Typography.label)
                            .foregroundStyle(Palette.symptom)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Layout.sm)
                .sensoryFeedback(.selection, trigger: kind)
            } header: {
                Text("What happened")
            }

            Section("How strong") {
                SteppedSlider(
                    values: Severity.allCases,
                    selection: $severity,
                    tint: Palette.symptom,
                    accessibilityLabel: "Severity",
                    title: { $0.title },
                    detail: { $0.detail }
                )
                .padding(.vertical, Layout.xs)
            }

            Section {
                // Quick offsets first: most reactions get logged some time after
                // they started, and doing that arithmetic in a date wheel is
                // exactly the friction that makes people give up and leave it
                // wrong.
                FlowLayout(spacing: Layout.sm) {
                    ForEach(quickOffsets, id: \.label) { offset in
                        Button {
                            occurredAt = Date().addingTimeInterval(-offset.seconds)
                        } label: {
                            Text(offset.label)
                                .font(Typography.captionEmphasis)
                                .foregroundStyle(Palette.symptom)
                                .padding(.horizontal, Layout.md)
                                .padding(.vertical, 7)
                                .background(Palette.symptom.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)

                DatePicker("Started", selection: $occurredAt, in: ...Date())

                Toggle("Track how long it lasted", isOn: $hasDuration.animation(Motion.quick))
                if hasDuration {
                    Stepper(value: $durationMinutes, in: 5...720, step: 5) {
                        LabeledContent("Lasted") {
                            Text(durationText)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            } header: {
                Text("When")
            } footer: {
                Text("Vessel looks back over the hours before this to see what you'd eaten, so the start time matters more than when you logged it.")
            }

            Section("Notes") {
                TextField("Anything worth remembering", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private var quickOffsets: [(label: String, seconds: TimeInterval)] {
        [("Now", 0), ("30 min ago", 1800), ("1 hr ago", 3600), ("2 hrs ago", 7200), ("This morning", morningOffset)]
    }

    /// Seconds back to 8am today, or to 8am yesterday if it's not yet morning.
    private var morningOffset: TimeInterval {
        let now = Date()
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let target = morning <= now ? morning : Calendar.current.date(byAdding: .day, value: -1, to: morning) ?? morning
        return now.timeIntervalSince(target)
    }

    private var durationText: String {
        durationMinutes < 60
            ? "\(durationMinutes) min"
            : "\(durationMinutes / 60)h \(durationMinutes % 60 == 0 ? "" : "\(durationMinutes % 60)m")"
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        kind = existing.kind
        if existing.kind.category != "Digestive" { showsAllCategories = true }
        severity = existing.severity
        occurredAt = existing.occurredAt
        note = existing.note ?? ""
        if let minutes = existing.durationMinutes {
            hasDuration = true
            durationMinutes = minutes
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.kind = kind
            existing.severity = severity
            existing.occurredAt = occurredAt
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote
            existing.durationMinutes = hasDuration ? durationMinutes : nil
        } else {
            context.insert(SymptomEntry(
                occurredAt: occurredAt,
                kind: kind,
                severity: severity,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                durationMinutes: hasDuration ? durationMinutes : nil
            ))
        }
        try? context.save()
    }
}


/// One symptom, as a tile: its symbol above its name.
private struct SymptomTile: View {
    let kind: SymptomKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Layout.sm) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 22)
                // Footnote weight, not subheadline: at a third of a phone's
                // width "Constipation" didn't fit and was hyphenated mid-word.
                Text(kind.title)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? Color.white : Palette.symptom)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, Layout.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Palette.symptom : Palette.symptom.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.symptom.opacity(isSelected ? 0 : 0.14), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1 : 0.98)
            .vesselAnimation(Motion.quick, value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
