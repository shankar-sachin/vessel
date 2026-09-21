import WidgetKit
import SwiftUI

/// The extension's entry point.
///
/// Only a Live Activity today. Home-screen widgets need an App Group to read the
/// app's SwiftData store, which a free developer account can't provision — so
/// they're deliberately absent rather than shipped broken.
@main
struct StreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakLiveActivity()
    }
}
