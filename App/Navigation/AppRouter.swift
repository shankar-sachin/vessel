import SwiftUI
import Observation

/// Navigation state, held in one observable object.
///
/// Centralized because Siri, Spotlight, the Live Activity and widgets all need
/// to deep-link into the app. Each of those hands the router a destination and
/// the UI follows, instead of every entry point poking at its own view state.
@MainActor
@Observable
final class AppRouter {

    /// The selected top-level section.
    var module: AppModule = .today

    /// Per-module navigation stacks, kept separate so switching tabs preserves
    /// where you were — returning to a tab and finding it reset is a small
    /// betrayal users notice immediately.
    var paths: [AppModule: NavigationPath] = [:]

    /// A sheet requested from anywhere in the app.
    var presentedSheet: SheetDestination?

    /// Set when something outside the app (Siri, a notification, the Live
    /// Activity) asked us to open a specific place.
    var pendingDeepLink: DeepLink?

    enum SheetDestination: Identifiable, Hashable {
        case quickLog
        case logFood
        case logWater
        case logSymptom
        case newJournalEntry
        case settings
        case capture
        /// A photo dropped onto the Diet log, read straight into capture.
        case captureImage(Data)

        var id: Self { self }
    }

    enum DeepLink: Hashable {
        case module(AppModule)
        case quickLog
        case logFood
        case logWater
        case logSymptom
        case streakDetail
    }

    func path(for module: AppModule) -> NavigationPath {
        paths[module] ?? NavigationPath()
    }

    func binding(for module: AppModule) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[module] ?? NavigationPath() },
            set: { self.paths[module] = $0 }
        )
    }

    /// `NavigationSplitView` sidebars bind to an *optional* selection, because a
    /// sidebar can legitimately have nothing selected. Vessel always has a
    /// current module, so this projection absorbs the nil rather than letting an
    /// optional leak through the whole app.
    var selectedModule: AppModule? {
        get { module }
        set { if let newValue { module = newValue } }
    }

    /// Tapping the already-selected tab pops that stack to its root, matching
    /// the system behaviour people expect everywhere else in iOS.
    func selectOrPopToRoot(_ target: AppModule) {
        if module == target {
            paths[target] = NavigationPath()
        } else {
            module = target
        }
    }

    func present(_ sheet: SheetDestination) {
        presentedSheet = sheet
    }

    /// The router of the window most recently brought to the front, for
    /// things that arrive from outside any window — a Spotlight result.
    static weak var frontmost: AppRouter?

    /// Parses a `vessel://` URL from a notification, the Live Activity, or Siri.
    ///
    /// Unrecognised URLs open the app at Today rather than doing nothing, so a
    /// stale link from an older build can't leave the user staring at a
    /// launch screen.
    func handle(deepLink url: URL) {
        guard url.scheme == "vessel" else { return }
        let segments = ([url.host()] + url.pathComponents.filter { $0 != "/" }).compactMap { $0 }

        switch segments {
        case ["log"], ["quick"]: handle(.quickLog)
        case ["log", "food"]:    handle(.logFood)
        case ["log", "water"]:   handle(.logWater)
        case ["log", "symptom"]: handle(.logSymptom)
        case ["streak"]:         handle(.streakDetail)
        case let s where s.first.flatMap(AppModule.init(rawValue:)) != nil:
            handle(.module(AppModule(rawValue: s[0])!))
        default:                 handle(.module(.today))
        }
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .module(let m):     module = m
        case .quickLog:          presentedSheet = .quickLog
        case .logFood:           module = .diet;    presentedSheet = .logFood
        case .logWater:          module = .water;   presentedSheet = .logWater
        case .logSymptom:        module = .dateLog; presentedSheet = .logSymptom
        case .streakDetail:      module = .today
        }
    }
}
