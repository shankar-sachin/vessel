import SwiftUI
import SwiftData
import VesselCore
import VesselDesign

/// Chooses the navigation structure that suits the current size.
///
/// This is a real branch rather than a tab bar stretched across an iPad: on a
/// large canvas a sidebar plus detail shows two levels of hierarchy at once,
/// which is the entire reason to use the bigger screen. The branch keys off
/// horizontal size class, not device idiom, so a split-screen iPad correctly
/// gets the compact layout.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompactRootView()
            } else {
                RegularRootView()
            }
        }
        .background(Palette.ground)
        .sheetDestinations()
    }
}

// MARK: - iPhone

private struct CompactRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: tabSelection) {
            ForEach(AppModule.allCases) { module in
                NavigationStack(path: router.binding(for: module)) {
                    ModuleScreen(module: module)
                }
                .tabItem {
                    Label(module.title, systemImage: router.module == module ? module.selectedSymbol : module.symbol)
                }
                .tag(module)
            }
        }
        .tint(router.module.tint)
    }

    /// Intercepts selection so tapping the current tab pops to root.
    private var tabSelection: Binding<AppModule> {
        Binding(
            get: { router.module },
            set: { router.selectOrPopToRoot($0) }
        )
    }
}

// MARK: - iPad

private struct RegularRootView: View {
    @Environment(AppRouter.self) private var router
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var router = router

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $router.selectedModule)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            NavigationStack(path: router.binding(for: router.module)) {
                ModuleScreen(module: router.module)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(router.module.tint)
    }
}

private struct SidebarView: View {
    @Binding var selection: AppModule?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppModule.allCases) { module in
                    NavigationLink(value: module) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(module.longTitle)
                                    .font(Typography.body)
                                Text(module.subtitle)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.inkTertiary)
                            }
                        } icon: {
                            Image(systemName: module.selectedSymbol)
                                .foregroundStyle(module.tint)
                        }
                    }
                    .tag(module)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Vessel")
    }
}

// MARK: - Module routing

/// Maps a module to its screen. One place, so every navigation surface agrees.
private struct ModuleScreen: View {
    let module: AppModule

    var body: some View {
        switch module {
        case .today:   TodayScreen()
        case .diet:    DietScreen()
        case .water:   WaterScreen()
        case .journal: JournalScreen()
        case .dateLog: DateLogScreen()
        }
    }
}

// MARK: - Sheets

private extension View {
    /// Sheets are attached once at the root rather than per-screen, so a deep
    /// link can open one regardless of where the user currently is.
    func sheetDestinations() -> some View {
        modifier(SheetDestinations())
    }
}

private struct SheetDestinations: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        @Bindable var router = router

        content.sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .logFood:         LogFoodSheet()
            case .logWater:        LogWaterSheet()
            case .logSymptom:      LogSymptomSheet()
            case .newJournalEntry: JournalEntrySheet()
            case .settings:        SettingsScreen()
            case .capture:         PlaceholderSheet(title: "Capture", tint: Palette.diet)
            }
        }
    }
}

/// Stands in for sheets arriving in later phases. Kept honest about what it is
/// rather than pretending to be a finished screen.
private struct PlaceholderSheet: View {
    let title: String
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "hammer",
                title: title,
                message: "This flow arrives in a later phase of the build.",
                tint: tint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("iPhone") {
    RootView()
        .environment(AppRouter())
        .modelContainer(VesselStore.previewContainer())
}
