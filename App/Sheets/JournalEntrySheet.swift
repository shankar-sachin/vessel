import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Writes or edits a journal entry.
///
/// Deliberately the least structured of the four sheets: the body field is large
/// and focused on open, and everything else is optional. A journal that demands
/// metadata before you can write a sentence doesn't get written in.
struct JournalEntrySheet: View {
    @Environment(\.modelContext) private var context

    var existing: JournalEntry?

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var mood: Mood = .steady
    @State private var hasMood = false
    @State private var tags: [String] = []
    @State private var didLoad = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        LogSheet(
            title: existing == nil ? "New entry" : "Edit entry",
            tint: Palette.journal,
            canSave: !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSave: save
        ) {
            Section {
                TextField("Title (optional)", text: $title)
                    .font(Typography.heading)

                TextField("How was today?", text: $body_, axis: .vertical)
                    .accessibilityIdentifier("journalBodyField")
                    .font(Typography.prose)
                    .proseLineSpacing()
                    .lineLimit(8...20)
                    .focused($bodyFocused)
            }

            Section {
                Toggle("Record a mood", isOn: $hasMood.animation(Motion.quick))
                if hasMood {
                    ScaleSelector(
                        values: Mood.allCases,
                        selection: $mood,
                        tint: Palette.journal,
                        style: .discrete,
                        title: { $0.title },
                        symbol: { $0.symbol }
                    )
                }
            } header: {
                Text("Mood")
            }

            Section("Tags") {
                TagEditor(tags: $tags, tint: Palette.journal)
            }
        }
        .onAppear {
            loadIfNeeded()
            // New entries open straight into the writing field; existing ones
            // don't, so the keyboard doesn't cover what you came back to read.
            if existing == nil { bodyFocused = true }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        title = existing.title ?? ""
        body_ = existing.body
        tags = existing.resolvedTags
        if let existingMood = existing.mood {
            hasMood = true
            mood = existingMood
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body_.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.title = trimmedTitle.isEmpty ? nil : trimmedTitle
            existing.body = trimmedBody
            existing.mood = hasMood ? mood : nil
            existing.tags = tags
            existing.updatedAt = Date()
        } else {
            context.insert(JournalEntry(
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                body: trimmedBody,
                mood: hasMood ? mood : nil,
                tags: tags
            ))
        }
        try? context.save()
    }
}
