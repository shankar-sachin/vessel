import Foundation
import SwiftData
import VesselCore

/// What the intents need from the app they run inside.
///
/// Intents live in this package so they can be tested, but a few things they
/// trigger belong to the app target — the streak's Live Activity and
/// notifications, and navigation. The app fills these in at launch; tests
/// swap the container for an in-memory one.
@MainActor
public enum IntentsRuntime {

    /// The store intents read and write. The app's own, by default.
    public static var container: ModelContainer = VesselStore.shared

    /// Called after an intent saves anything, so the streak surfaces update
    /// the same way they do after logging in the app.
    public static var didLog: (@MainActor (ModelContext) async -> Void)?

    /// Called when a Spotlight result for a meal is opened.
    public static var openMeal: (@MainActor (UUID) -> Void)?

    static var context: ModelContext { container.mainContext }
}
