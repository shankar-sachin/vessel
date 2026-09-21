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

    var body: some View {
        LogSheet(
            title: existing == nil ? "Log a reaction" : "Edit reaction",
            tint: Palette.symptom,
            canSave: true,
            onSave: save
        ) {
            Section("What happened") {
                ForEach(visibleGroups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: Layout.sm) {
                        Text(group.category)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)

                        FlowLayout(spacing: Layout.sm) {
                            ForEach(group.kinds) { candidate in
                                Button {
                                    kind = candidate
                                } label: {
                                    Label(candidate.title, systemImage: candidate.symbol)
                                        .font(Typography.captionEmphasis)
                                        .foregroundStyle(kind == candidate ? .white : Palette.symptom)
                                        .padding(.horizontal, Layout.md)
                                        .padding(.vertical, 7)
                                        .background(
                                            kind == candidate ? Palette.symptom : Palette.symptom.opacity(0.12),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(kind == candidate ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !showsAllCategories {
                    Button {
                        withAnimation(Motion.standard) { showsAllCategories = true }
                    } label: {
                        Label("Other symptoms", systemImage: "ellipsis.circle")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.symptom)
                    }
                }
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
