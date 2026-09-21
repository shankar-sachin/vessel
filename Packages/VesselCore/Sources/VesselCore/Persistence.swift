import Foundation
import SwiftData

/// Owns the SwiftData stack.
public enum VesselStore {

    /// Every persistent type in the app. Adding a model here is the only place
    /// registration happens.
    public static let schema = Schema([
        FoodEntry.self,
        FoodItem.self,
        WaterEntry.self,
        JournalEntry.self,
        SymptomEntry.self,
        UserProfile.self,
        LearnedAlias.self
    ])

    /// The app's on-disk container.
    ///
    /// Local-only today. The schema is already written to CloudKit's rules, so
    /// turning sync on later means adding a `cloudKitDatabase:` argument here and
    /// nothing else — no migration, no model changes.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// A container that survives a corrupt or incompatible store.
    ///
    /// If the store can't be opened we move it aside and start fresh rather than
    /// crashing on launch. A user who hits a bad migration gets a working app and
    /// a recoverable file on disk; the alternative is an app that won't open at
    /// all, which is the one failure mode you can't apologise your way out of.
    public static func makeContainerRecoveringFromFailure() -> ModelContainer {
        do {
            return try makeContainer()
        } catch {
            quarantineStore(reason: error)
            do {
                return try makeContainer()
            } catch {
                // Disk is unusable. In-memory keeps the app running for this
                // session so the user can at least export or see what's there.
                return try! makeContainer(inMemory: true)
            }
        }
    }

    /// Renames the existing store so the next open starts clean, keeping the old
    /// file for recovery.
    private static func quarantineStore(reason: Error) {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let storeURL = appSupport.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        // SwiftData keeps sidecar files alongside the store; all three must move
        // together or the "fresh" store inherits the broken write-ahead log.
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = appSupport.appendingPathComponent("corrupt-\(stamp).store\(suffix)")
            try? fm.moveItem(at: source, to: destination)
        }
    }

    /// An in-memory container seeded for previews and tests.
    @MainActor
    public static func previewContainer() -> ModelContainer {
        // Previews must never fail to render, so fall back to an empty container
        // rather than trapping if seeding throws.
        guard let container = try? makeContainer(inMemory: true) else {
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
        SampleData.seed(into: container.mainContext)
        return container
    }
}
