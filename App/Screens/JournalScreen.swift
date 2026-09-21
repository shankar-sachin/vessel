import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// The Journal. Set in a serif face and given more line spacing than the rest of
/// the app — this is the one place in Vessel meant for reading rather than
/// scanning, and it should feel different under the eye.
struct JournalScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]

    @State private var editingEntry: JournalEntry?

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    icon: "book.closed",
                    title: "Nothing written yet",
                    message: "A line or two about how the day went is enough to make patterns visible later.",
                    tint: Palette.journal
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Layout.md) {
                        ForEach(entries) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                JournalCard(entry: entry)
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
                    .screenGutter()
                    .padding(.vertical, Layout.lg)
                    .readableWidth(sizeClass == .compact ? .infinity : Layout.readableWidth)
                }
            }
        }
        .background(Palette.ground)
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.present(.newJournalEntry) } label: {
                    Label("New entry", systemImage: "square.and.pencil")
                }
                .tint(Palette.journal)
            }
        }
        .sheet(item: $editingEntry) { entry in
            JournalEntrySheet(existing: entry)
        }
    }
}

private struct JournalCard: View {
    let entry: JournalEntry

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.sm) {
                HStack(spacing: Layout.sm) {
                    Text(entry.createdAt, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(Palette.journal)
                    Spacer()
                    if let mood = entry.mood {
                        Label(mood.title, systemImage: mood.symbol)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }

                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(Typography.heading)
                        .foregroundStyle(Palette.ink)
                }

                Text(entry.body)
                    .font(Typography.prose)
                    .foregroundStyle(Palette.inkSecondary)
                    .proseLineSpacing()
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                if !entry.resolvedTags.isEmpty {
                    HStack(spacing: Layout.xs) {
                        ForEach(entry.resolvedTags, id: \.self) { tag in
                            VesselChip(tag, tint: Palette.journal)
                        }
                    }
                    .padding(.top, Layout.xs)
                }
            }
        }
    }
}
