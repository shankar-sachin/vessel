import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselIntents

@main
struct VesselApp: App {

    @MainActor private static var didBootstrap = false

    /// Shared with Siri, which runs intents in this same process.
    private let container: ModelContainer = VesselStore.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Navigation titles are styled through UIKit's appearance proxy, which
        // must be set before the first bar is created.
        VesselAppearance.configure()

        // Background task registration has to happen before launch completes, so
        // it can't wait for a `.task` modifier.
        StreakCoordinator.registerBackgroundTask(container: container)

        // Siri runs intents in this process, sometimes with no window open.
        // Logging by voice has to refresh the streak exactly as logging in the
        // app does, and a Spotlight result has to open the right screen.
        IntentsRuntime.container = container
        IntentsRuntime.didLog = { context in
            await StreakCoordinator.refresh(context: context)
        }
        // Whichever window was last in front: with several windows open on
        // iPad, a Spotlight result opens in the one the user was just using.
        IntentsRuntime.openMeal = { _ in
            AppRouter.frontmost?.selectOrPopToRoot(.diet)
        }
        VesselShortcuts.updateAppShortcutParameters()
        WatchBridge.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            // Each window owns its navigation, so two windows on iPad can sit
            // on different modules without dragging each other along.
            SceneRoot()
                .tint(Palette.water)
                .task { await bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    let context = container.mainContext
                    switch phase {
                    case .active:
                        // Returning to the app is the most reliable moment we get
                        // to bring the Live Activity up to date, and to pick up
                        // anything another device left in the backup folder.
                        Task {
                            await BackupCoordinator.shared.syncOnAppear(context: context)
                            await StreakCoordinator.refresh(context: context)
                        }
                    case .background:
                        BackupCoordinator.shared.syncOnBackground(context: context)
                    default:
                        break
                    }
                }
        }
        .modelContainer(container)
        .commands { VesselCommands() }
    }

    /// First-run setup.
    ///
    /// Creating the profile here rather than lazily at each read site means every
    /// screen can assume settings exist, and the defaults are written down in one
    /// place instead of scattered as fallbacks.
    @MainActor
    private func bootstrap() async {
        // Once per launch, not once per window.
        guard !Self.didBootstrap else { return }
        Self.didBootstrap = true
        let context = container.mainContext
        _ = UserProfile.current(in: context)

        #if DEBUG
        // Seed the simulator with a realistic week so the UI can be developed and
        // reviewed against something other than empty state. Never runs in a
        // release build, and never runs over existing data.
        // Tests that check the upgrade card start from a fresh, undismissed card.
        if ProcessInfo.processInfo.environment["VESSEL_RESET_UPGRADE_PROMPT"] == "1" {
            UserProfile.current(in: context).didDismissUpgradePrompt = false
            try? context.save()
        }
        if ProcessInfo.processInfo.environment["VESSEL_SEED_SAMPLE_DATA"] == "1" {
            let existing = try? context.fetchCount(FetchDescriptor<FoodEntry>())
            if (existing ?? 0) == 0 {
                SampleData.seed(into: context)
            }
        }
        #endif

        await BackupCoordinator.shared.syncOnAppear(context: context)
        await StreakCoordinator.refresh(context: context)
        StreakCoordinator.scheduleBackgroundRefresh(context: context)
    }
}
