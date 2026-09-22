import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselInsights

/// The Date Log: symptoms and reactions, and what they correlate with.
struct DateLogScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @Query(sort: \SymptomEntry.occurredAt, order: .reverse) private var entries: [SymptomEntry]
    // The correlation engine needs the other side of the question. Both logs
    // are fetched here rather than inside the insights view so SwiftData
    // observes them and the findings update as things are logged.
    @Query(sort: \FoodEntry.loggedAt) private var meals: [FoodEntry]
    @Query(sort: \WaterEntry.loggedAt) private var drinks: [WaterEntry]

    @State private var editingEntry: SymptomEntry?

    private var grouped: [(day: Date, entries: [SymptomEntry])] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.occurredAt) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    icon: "stethoscope",
                    title: "No reactions logged",
                    message: "Record how you felt after eating. Once there's a few weeks of it, Vessel can start looking for patterns.",
                    tint: Palette.symptom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Layout.lg) {
                        InsightsSection(meals: meals, drinks: drinks, symptoms: entries)

                        ForEach(grouped, id: \.day) { group in
                            VStack(alignment: .leading, spacing: Layout.sm) {
                                Text(group.day, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                                    .font(Typography.title)
                                    .foregroundStyle(Palette.ink)
                                ForEach(group.entries) { entry in
                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        SymptomCard(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            editingEntry = entry
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            context.delete(entry)
                                            try? context.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
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
        .navigationTitle("Date Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.present(.logSymptom) } label: {
                    Label("Log reaction", systemImage: "plus")
                }
                .tint(Palette.symptom)
            }
        }
        .sheet(item: $editingEntry) { entry in
            LogSymptomSheet(existing: entry)
        }
    }
}

private struct SymptomCard: View {
    let entry: SymptomEntry

    var body: some View {
        VesselCard(padding: Layout.md) {
            HStack(alignment: .top, spacing: Layout.md) {
                Image(systemName: entry.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Palette.symptom)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: Layout.xs) {
                    HStack {
                        Text(entry.kind.title)
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(entry.occurredAt, format: .dateTime.hour().minute())
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }

                    SeverityBar(severity: entry.severity)

                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let minutes = entry.durationMinutes {
                        Text("Lasted about \(minutes) minutes")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind.title), \(entry.severity.title)")
    }
}

/// Five pips rather than a number — severity is ordinal, and pips make that
/// obvious without implying the difference between 2 and 3 is measurable.
private struct SeverityBar: View {
    let severity: Severity

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Severity.allCases) { level in
                Capsule()
                    .fill(level.rawValue <= severity.rawValue ? Palette.symptom : Palette.symptom.opacity(0.15))
                    .frame(width: 16, height: 4)
            }
            Text(severity.title)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.leading, Layout.xs)
        }
        .accessibilityElement()
        .accessibilityLabel("Severity")
        .accessibilityValue(severity.title)
    }
}
