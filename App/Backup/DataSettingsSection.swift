import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import VesselCore
import VesselDesign

/// The "Your data" part of Settings: automatic backup, manual export, import.
///
/// Given that Vessel keeps everything on-device, this section is the difference
/// between "private" and "one lost phone from gone", so it's deliberately
/// explicit about what is and isn't happening.
struct DataSettingsSection: View {
    @Environment(\.modelContext) private var context

    @State private var isChoosingFolder = false
    @State private var isImporting = false
    @State private var exportURL: URL?
    @State private var status: StatusMessage?
    /// Bumped to force the folder/date rows to re-read after a change.
    @State private var refreshToken = 0

    private var coordinator: BackupCoordinator { .shared }

    struct StatusMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isError: Bool
    }

    var body: some View {
        Section {
            if let folderName = folderName {
                LabeledContent("Backup folder") {
                    Text(folderName)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Last backup") {
                    Text(lastBackupText)
                        .foregroundStyle(Palette.inkSecondary)
                }

                Button("Back up now") { backUpNow() }

                Button("Stop backing up", role: .destructive) {
                    coordinator.clearFolder()
                    refreshToken += 1
                }
            } else {
                Button("Choose a folder for Vessel…") { isChoosingFolder = true }
            }
        } header: {
            Text("Automatic backup")
        } footer: {
            if folderName == nil {
                Text("Pick a folder and Vessel saves a copy of everything there each time you leave the app. Choose somewhere in iCloud Drive and your other devices will pick it up automatically.")
            } else {
                // Saying plainly what this is and isn't, so nobody assumes it's
                // live sync and loses an edit expecting otherwise.
                Text("Vessel writes a copy here when you leave the app, and merges anything your other devices left. It's not live sync — if you edit the same entry on two devices, the first one wins.")
            }
        }

        Section {
            Button("Export a copy…") { prepareExport() }
            Button("Import from a file…") { isImporting = true }
        } header: {
            Text("Manual")
        } footer: {
            Text("Exports everything as plain JSON — readable by anything, not just Vessel. Importing merges rather than replaces, so nothing you already have is lost or duplicated.")
        }
        .id(refreshToken)
        // Folder picker for the backup destination.
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try coordinator.setFolder(url)
                    backUpNow()
                } catch {
                    status = StatusMessage(
                        title: "Couldn't use that folder",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            case .failure(let error):
                status = StatusMessage(title: "Couldn't use that folder",
                                       message: error.localizedDescription, isError: true)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(url: url)
        }
        .alert(item: $status) { status in
            Alert(
                title: Text(status.title),
                message: Text(status.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Derived

    private var folderName: String? {
        _ = refreshToken
        return coordinator.folderDisplayName
    }

    private var lastBackupText: String {
        guard let date = coordinator.lastBackupDate else { return "Not yet" }
        return date.formatted(.relative(presentation: .named))
    }

    // MARK: - Actions

    private func backUpNow() {
        let ok = coordinator.writeBackup(from: context)
        refreshToken += 1
        if !ok {
            status = StatusMessage(
                title: "Backup failed",
                message: "Vessel couldn't write to that folder. It may have been moved, renamed, or deleted — try choosing it again.",
                isError: true
            )
        }
    }

    private func prepareExport() {
        do {
            let data = try ArchiveService.exportData(from: context, includingImages: true)
            let name = "Vessel-\(Date().formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            status = StatusMessage(title: "Export failed",
                                   message: error.localizedDescription, isError: true)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                status = StatusMessage(title: "Import failed",
                                       message: error.localizedDescription, isError: true)
            }
            return
        }

        // A file coming from outside the sandbox needs its scope opened.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let summary = try ArchiveService.importData(data, into: context)
            status = StatusMessage(
                title: "Imported",
                message: summary.added == 0
                    ? "Everything in that file was already here."
                    : "Added \(summary.added) entr\(summary.added == 1 ? "y" : "ies")."
                      + (summary.skipped > 0 ? " Skipped \(summary.skipped) already present." : ""),
                isError: false
            )
            Task { await StreakCoordinator.refresh(context: context) }
        } catch {
            status = StatusMessage(title: "Import failed",
                                   message: error.localizedDescription, isError: true)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Wraps `UIActivityViewController`, since SwiftUI's `ShareLink` can't present
/// a temporary file from inside a `Form` row reliably on iPad without an anchor.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
