import Foundation
import SwiftData
import VesselCore

#if canImport(UIKit)
import UIKit
#endif

/// Automatic backup into a folder the user chooses once.
///
/// This is Vessel's stand-in for iCloud sync on a free developer account.
/// CloudKit needs a paid membership, but a folder the user picked through the
/// system document picker needs no entitlement at all — and if they pick one
/// inside iCloud Drive, iCloud does the syncing for us.
///
/// ### How two devices meet
///
/// Each install writes to its *own* file (`Vessel-backup-<installID>.json`)
/// rather than a shared one. Two devices writing the same filename into iCloud
/// Drive would produce conflict copies and lose data; writing separate files
/// means they never collide, and each device simply merges whatever other files
/// it finds. Import is merge-by-id and idempotent, so re-reading the same file
/// changes nothing.
///
/// The honest limitation: this is eventual, file-level sharing, not real sync.
/// If the *same* entry is edited on two devices, the one already present wins.
/// Real conflict resolution is what CloudKit would buy.
@MainActor
final class BackupCoordinator {

    static let shared = BackupCoordinator()

    private enum Keys {
        static let folderBookmark = "vessel.backup.folderBookmark"
        static let installID = "vessel.backup.installID"
        static let lastBackupAt = "vessel.backup.lastBackupAt"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Install identity

    /// A stable id for this install, used to name our own backup file.
    ///
    /// Generated rather than using `identifierForVendor`, which can change when
    /// every app from a vendor is deleted — that would orphan the old backup and
    /// silently start a second one.
    var installID: String {
        if let existing = defaults.string(forKey: Keys.installID) { return existing }
        let generated = String(UUID().uuidString.prefix(8))
        defaults.set(generated, forKey: Keys.installID)
        return generated
    }

    private var deviceLabel: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Mac"
        #endif
    }

    private var ownFileName: String { "Vessel-backup-\(installID).json" }

    // MARK: - Folder selection

    var isConfigured: Bool { defaults.data(forKey: Keys.folderBookmark) != nil }

    var lastBackupDate: Date? {
        defaults.object(forKey: Keys.lastBackupAt) as? Date
    }

    /// Remembers the folder the user picked.
    ///
    /// Stored as a bookmark rather than a path because sandboxed apps lose
    /// access to a bare URL across launches.
    func setFolder(_ url: URL) throws {
        // The picker hands back a security-scoped URL; we must hold the scope
        // open while creating the bookmark or it resolves to nothing later.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Keys.folderBookmark)
    }

    func clearFolder() {
        defaults.removeObject(forKey: Keys.folderBookmark)
        defaults.removeObject(forKey: Keys.lastBackupAt)
    }

    /// Resolves the stored folder, refreshing the bookmark if it went stale.
    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Keys.folderBookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            // The folder moved or was renamed; re-record it so the next launch
            // doesn't silently stop backing up.
            try? setFolder(url)
        }
        return url
    }

    /// Display name for Settings.
    var folderDisplayName: String? {
        resolveFolder()?.lastPathComponent
    }

    // MARK: - Writing

    /// Writes this device's backup. Safe to call often; cheap and overwrites.
    @discardableResult
    func writeBackup(from context: ModelContext) -> Bool {
        guard let folder = resolveFolder() else { return false }

        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        do {
            let archive = try ArchiveService.export(from: context, includingImages: true)
            let data = try ArchiveService.makeEncoder().encode(archive)

            let destination = folder.appendingPathComponent(ownFileName)
            // Atomic so a backup interrupted mid-write can't replace a good file
            // with a truncated one.
            try data.write(to: destination, options: .atomic)

            defaults.set(Date(), forKey: Keys.lastBackupAt)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reading

    /// Merges every *other* device's backup found in the folder.
    ///
    /// - Returns: what was pulled in, or nil if no folder is configured.
    @discardableResult
    func mergeOtherDevices(into context: ModelContext) -> ArchiveService.ImportSummary? {
        guard let folder = resolveFolder() else { return nil }

        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var combined = ArchiveService.ImportSummary()

        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix("Vessel-backup-"), name.hasSuffix(".json") else { continue }
            // Never re-import our own file — it would be a no-op, but reading it
            // wastes time proportional to the whole history on every launch.
            guard name != ownFileName else { continue }

            // A file still downloading from iCloud reads as empty; ask for it and
            // move on rather than importing nothing and calling it success.
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }

            guard let data = try? Data(contentsOf: url) else { continue }
            // Settings are not restored from another device's backup — that
            // would let an iPad silently rewrite the iPhone's fasting plan.
            if let summary = try? ArchiveService.importData(data, into: context, restoringSettings: false) {
                combined.added += summary.added
                combined.skipped += summary.skipped
            }
        }

        return combined
    }

    // MARK: - Lifecycle

    /// Called on launch and when returning to the foreground.
    func syncOnAppear(context: ModelContext) async {
        guard isConfigured else { return }
        _ = mergeOtherDevices(into: context)
    }

    /// Called when the app goes to the background.
    func syncOnBackground(context: ModelContext) {
        guard isConfigured else { return }
        writeBackup(from: context)
    }
}
