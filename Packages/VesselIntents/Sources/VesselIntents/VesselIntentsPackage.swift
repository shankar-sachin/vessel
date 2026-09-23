import AppIntents

/// Makes this package's intents, entities and enums visible to the system.
///
/// App Intents are discovered from metadata extracted at build time. Intents
/// in a Swift package are only found when the app declares the package, which
/// it does through its own `AppIntentsPackage` listing this one.
public struct VesselIntentsPackage: AppIntentsPackage {}
