import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselIntents

@main
struct VesselApp: App {

    /// Shared with Siri, which runs intents in this same process.
    private let container: ModelContainer = VesselStore.shared

    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // One router, created here so the Spotlight hook below holds the same
        // instance SwiftUI does, without reading `@State` before it's installed.
        let router = AppRouter()
        _router = State(initialValue: router)

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
        IntentsRuntime.openMeal = { _ in
            router.selectOrPopToRoot(.diet)
        }
        VesselShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Palette.water)
                .task { await bootstrap() }
                .onOpenURL { router.handle(deepLink: $0) }
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
    }

    /// First-run setup.
    ///
    /// Creating the profile here rather than lazily at each read site means every
    /// screen can assume settings exist, and the defaults are written down in one
    /// place instead of scattered as fallbacks.
    @MainActor
    private func bootstrap() async {
        let context = container.mainContext
        _ = UserProfile.current(in: context)

        #if DEBUG
        // Seed the simulator with a realistic week so the UI can be developed and
        // reviewed against something other than empty state. Never runs in a
        // release build, and never runs over existing data.
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
