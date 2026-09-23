import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Logs water with a custom amount.
///
/// Water only. The quick-add tiles cover the common pours; this is for an
/// odd-sized glass or a backdated one. Anything else a person drinks — coffee,
/// milk, juice, beer — is food with a nutrition label and belongs in the Diet
/// log, which is why this sheet no longer takes a free-text name or caffeine
/// and alcohol toggles: they existed only so other drinks could be filed here.
struct LogWaterSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    /// Editing an existing drink when set.
    var existing: WaterEntry?

    @State private var volumeML: Double = 250
    @State private var loggedAt: Date = Date()
    @State private var didLoad = false

    private var isMetric: Bool { (profiles.first?.unitSystem ?? .metric) == .metric }

    /// Common pours, offered as shortcuts inside the sheet too.
    private let presets: [Double] = [150, 250, 330, 500, 750, 1000]

    var body: some View {
        LogSheet(
            title: existing == nil ? "Add water" : "Edit water",
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

            Section {
                DatePicker("Time", selection: $loggedAt, in: ...Date())
            } footer: {
                Text("Coffee, milk, juice and other drinks go in the Diet log, with their nutrition.")
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
        loggedAt = existing.loggedAt
    }

    private func save() {
        if let existing {
            existing.volumeML = volumeML
            existing.loggedAt = loggedAt
        } else {
            context.insert(WaterEntry(
                loggedAt: loggedAt,
                volumeML: volumeML,
                source: .manual,
                containerName: Self.containerName(for: volumeML)
            ))
        }
        try? context.save()
    }

    /// Named after the Water screen's own tiles when the amount matches one,
    /// so the day's list reads "Glass", "Bottle" rather than bare numbers.
    static func containerName(for millilitres: Double) -> String {
        switch millilitres {
        case 250: return "Glass"
        case 500: return "Bottle"
        case 750: return "Large"
        default: return "Water"
        }
    }
}
