import AppIntents
import CoreLocation
import Foundation
import SwiftData
import VesselCore

/// Vessel's journal, described in the shape Apple Intelligence understands.
///
/// Conforming to the system's journal schema lets the assistant create entries
/// from anywhere — "add that to my journal" — without a phrase naming the app.
/// The shape is fixed by the schema and validated at build time: these exact
/// parameters, even the ones Vessel stores nowhere (location, media), which are
/// accepted and folded into the text or dropped.
@available(iOS 18.0, macOS 15.0, *)
@AppEntity(schema: .journal.entry)
public struct JournalEntryEntity: Identifiable {
    public static let defaultQuery = JournalEntryQuery()

    public var id: UUID
    public var title: String?
    public var message: AttributedString?
    public var mediaItems: [IntentFile]
    public var entryDate: Date?
    public var location: CLPlacemark?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title ?? "Journal entry")")
    }

    @MainActor
    init(entry: JournalEntry) {
        id = entry.id
        title = entry.title
        message = AttributedString(entry.body)
        mediaItems = []
        entryDate = entry.createdAt
        location = nil
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct JournalEntryQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [UUID]) async throws -> [JournalEntryEntity] {
        let wanted = Set(identifiers)
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { wanted.contains($0.id) })
        return ((try? IntentsRuntime.context.fetch(descriptor)) ?? []).map(JournalEntryEntity.init(entry:))
    }
}

@available(iOS 18.0, macOS 15.0, *)
@AppIntent(schema: .journal.createEntry)
public struct CreateJournalEntryIntent {
    public var title: String?
    public var message: AttributedString
    public var mediaItems: [IntentFile]
    public var entryDate: Date?
    public var location: CLPlacemark?

    public init() {}

    @MainActor
    public func perform() async throws -> some ReturnsValue<JournalEntryEntity> {
        var body = String(message.characters)
        if let place = location?.name { body += "\n\n\(place)" }
        let entry = JournalEntry(createdAt: entryDate ?? Date(), title: title, body: body)
        let context = IntentsRuntime.context
        context.insert(entry)
        try? context.save()
        return .result(value: JournalEntryEntity(entry: entry))
    }
}
