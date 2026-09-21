import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Logs a drink with a custom amount.
///
/// The quick-add tiles on the Water screen cover the common cases; this is for
/// everything else — an odd-sized cup, a coffee, a backdated drink.
struct LogWaterSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    /// Editing an existing drink when set.
    var existing: WaterEntry?

    @State private var volumeML: Double = 250
    @State private var containerName: String = "Glass"
    @State private var loggedAt: Date = Date()
    @State private var containsCaffeine = false
    @State private var containsAlcohol = false
    @State private var didLoad = false

    private var isMetric: Bool { (profiles.first?.unitSystem ?? .metric) == .metric }

    /// Common pours, offered as shortcuts inside the sheet too.
    private let presets: [Double] = [150, 250, 330, 500, 750, 1000]

    var body: some View {
        LogSheet(
            title: existing == nil ? "Add a drink" : "Edit drink",
            tint: Palette.water,
            canSave: volumeML > 0,
            onSave: save
        ) {
            Section {
                FormRow("Amount") {
                    HStack(spacing: Layout.sm) {
                        TextField("0", value: $volumeML.blankWhenZero, format: .number.precision(.fractionLength(0)))
                            .accessibilityIdentifier("waterAmountField")
                            .keyboardType(.numberPad)
                            .font(Typography.metricSmall)
                            .foregroundStyle(Palette.water)
                        Text(isMetric ? "ml" : "fl oz equivalent, stored as ml")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }

                // Tapping a preset is faster than typing, and covers most entries.
                FlowLayout(spacing: Layout.sm) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            volumeML = preset
                        } label: {
                            Text("\(Int(preset)) ml")
                                .font(Typography.captionEmphasis)
                                .foregroundStyle(volumeML == preset ? .white : Palette.water)
                                .padding(.horizontal, Layout.md)
                                .padding(.vertical, 7)
                                .background(
                                    volumeML == preset ? Palette.water : Palette.water.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Details") {
                TextField("Container, e.g. Mug", text: $containerName)
                DatePicker("Time", selection: $loggedAt, in: ...Date())
            }

            Section {
                Toggle("Contains caffeine", isOn: $containsCaffeine)
                Toggle("Contains alcohol", isOn: $containsAlcohol)
            } footer: {
                // These aren't judgements — they're inputs to the Date Log's
                // correlation engine, which is worth saying so people flag them
                // honestly rather than defensively.
                Text("Vessel counts these toward hydration, and can also check them against how you felt later.")
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        // Guarded because `onAppear` fires again when the sheet returns from
        // backgrounding, which would otherwise discard the user's edits.
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        volumeML = existing.volumeML
        containerName = existing.containerName ?? ""
        loggedAt = existing.loggedAt
        containsCaffeine = existing.containsCaffeine
        containsAlcohol = existing.containsAlcohol
    }

    private func save() {
        let name = containerName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.volumeML = volumeML
            existing.containerName = name.isEmpty ? nil : name
            existing.loggedAt = loggedAt
            existing.containsCaffeine = containsCaffeine
            existing.containsAlcohol = containsAlcohol
        } else {
            context.insert(WaterEntry(
                loggedAt: loggedAt,
                volumeML: volumeML,
                source: .manual,
                containerName: name.isEmpty ? nil : name,
                containsCaffeine: containsCaffeine,
                containsAlcohol: containsAlcohol
            ))
        }
        try? context.save()
    }
}
