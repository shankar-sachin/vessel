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
        LearnedAlias.self,
        FoodPairing.self
    ])

    /// The one container for the whole process.
    ///
    /// Siri runs intents inside the app's process, sometimes before any
    /// window exists. Two containers on the same store in one process each
    /// keep their own view of it, so an entry logged by voice might not show
    /// up in the open app until relaunch. Everything shares this one instead.
    public static let shared: ModelContainer = makeContainerRecoveringFromFailure()

    /// The app's on-disk container.
    ///
    /// Local-only today, because CloudKit needs a paid Apple Developer Program
    /// membership and this app is signed with a free personal team. Until then
    /// `BackupCoordinator` covers cross-device data via a user-chosen folder.
    ///
    /// ### Turning on real iCloud sync
    ///
    /// Once the membership exists, this is the whole change:
    ///
    /// 1. Add the iCloud capability with CloudKit to the app target in
    ///    `project.yml`, plus an `iCloud.com.sachinshankar.vessel` container.
    /// 2. Change the configuration below to
    ///    `.private("iCloud.com.sachinshankar.vessel")`.
    ///
    /// No migration and no model edits, because the schema already follows
    /// CloudKit's rules — every property defaulted or optional, no unique
    /// attributes, every relationship optional with an inverse. That was the
    /// point of writing it that way from the start.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
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
