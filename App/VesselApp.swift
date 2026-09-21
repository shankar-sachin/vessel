import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

@main
struct VesselApp: App {

    /// Built once at launch, recovering rather than crashing if the store is bad.
    private let container: ModelContainer = VesselStore.makeContainerRecoveringFromFailure()

    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Navigation titles are styled through UIKit's appearance proxy, which
        // must be set before the first bar is created.
        VesselAppearance.configure()

        // Background task registration has to happen before launch completes, so
        // it can't wait for a `.task` modifier.
        StreakCoordinator.registerBackgroundTask(container: container)
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
