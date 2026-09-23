import SwiftUI
import VesselDesign

/// One window's worth of Vessel: its own navigation, deep links and focus.
struct SceneRoot: View {
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootView()
            .environment(router)
            .focusedSceneValue(\.router, router)
            .onOpenURL { router.handle(deepLink: $0) }
            .onAppear { AppRouter.frontmost = router }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { AppRouter.frontmost = router }
            }
    }
}

extension FocusedValues {
    /// The focused window's router, for menu and keyboard commands.
    @Entry var router: AppRouter?
}

/// Keyboard shortcuts, shown in the ⌘-hold overlay on iPad.
///
/// Logging is the thing people come to do, so it gets the obvious keys; the
/// modules get ⌘1–5 in the order they appear.
struct VesselCommands: Commands {
    @FocusedValue(\.router) private var router

    var body: some Commands {
        CommandMenu("Log") {
            Button("Quick Log") { router?.present(.quickLog) }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add Water") { router?.handle(.logWater) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Log a Reaction") { router?.handle(.logSymptom) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("New Journal Entry") { router?.present(.newJournalEntry) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("From a Photo") { router?.present(.capture) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            ForEach(Array(AppModule.allCases.enumerated()), id: \.element) { index, module in
                Button(module.title) { router?.selectOrPopToRoot(module) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
