import SwiftUI
import VesselDesign

/// Vessel on the wrist: the day at a glance, water in one tap, and a meal
/// said out loud.
@main
struct VesselWatchApp: App {
    @State private var store = WatchStore.shared
    @State private var page = VesselWatchApp.initialPage

    /// DEBUG: `-page water` or `-page log` opens straight onto that page, so
    /// each can be screenshotted without driving the Digital Crown.
    private static var initialPage: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count {
            return ["today": 0, "water": 1, "log": 2][args[i + 1]] ?? 0
        }
        #endif
        return 0
    }

    init() {
        WatchStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $page) {
                TodayPage().tag(0)
                WaterPage().tag(1)
                LogPage().tag(2)
            }
            .tabViewStyle(.verticalPage)
            .environment(store)
        }
    }
}
