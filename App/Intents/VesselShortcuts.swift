import AppIntents
import VesselIntents

/// Declares the intents package to the system. App Intents only discovers
/// intents in a Swift package when the app lists it here.
struct VesselAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [VesselIntentsPackage.self]
    }
}

/// What can be said to Siri, with no setup.
///
/// Phrases must name the app, and only enum and entity parameters can sit
/// inside one — free text can't. So "Log a bottle of water in Vessel" works
/// in a single breath, while a meal is "Log a meal in Vessel" followed by
/// Siri asking what you had. That second turn is where the parser earns its
/// keep: the answer can be as loose as it would be in the app.
struct VesselShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
                "Log something in \(.applicationName)",
                "Add to \(.applicationName)",
                "Tell \(.applicationName) what I ate"
            ],
            shortTitle: "Log a Meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log a \(\.$serving) of water in \(.applicationName)",
                "Add a \(\.$serving) of water to \(.applicationName)",
                "Log water in \(.applicationName)"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogSymptomIntent(),
            phrases: [
                "Log \(\.$symptom) in \(.applicationName)",
                "I have \(\.$symptom) in \(.applicationName)",
                "Log a reaction in \(.applicationName)"
            ],
            shortTitle: "Log a Reaction",
            systemImageName: "stethoscope"
        )
        AppShortcut(
            intent: AddJournalEntryIntent(),
            phrases: [
                "Add a journal entry in \(.applicationName)",
                "Write in my \(.applicationName) journal"
            ],
            shortTitle: "Journal Entry",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: CheckIntakeIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "Check my day in \(.applicationName)",
                "How much have I eaten in \(.applicationName)"
            ],
            shortTitle: "How Am I Doing",
            systemImageName: "chart.bar"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
