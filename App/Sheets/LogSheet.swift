import SwiftUI
import VesselDesign

/// The shared frame every logging sheet sits in.
///
/// Centralised so all four logs behave identically: same ground, same toolbar
/// placement, same disabled-save rule, same cancel semantics. When the flows
/// diverge in small ways, people stop trusting that they know what a button
/// will do.
struct LogSheet<Content: View>: View {

    private let title: String
    private let tint: Color
    private let saveLabel: String
    /// Save is disabled until the entry is actually valid, rather than letting
    /// it fail after the fact.
    private let canSave: Bool
    private let onSave: () -> Void
    private let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        tint: Color,
        saveLabel: String = "Save",
        canSave: Bool,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tint = tint
        self.saveLabel = saveLabel
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .tint(tint)
        }
        // Medium detent where the form is short, so the sheet doesn't cover the
        // whole screen for a two-field entry.
        .presentationDragIndicator(.visible)
    }
}

/// A labelled row wrapping a custom control, matching `LabeledContent`'s
/// alignment so mixed forms stay visually regular.
struct FormRow<Content: View>: View {
    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.inkSecondary)
            content
        }
        .padding(.vertical, 2)
    }
}
