import Foundation

/// What the watch and the phone say to each other.
///
/// The watch never writes to a store of its own. It sends what was said — the
/// raw sentence, or an amount of water — and the phone saves it through the
/// same writer as Quick log and Siri. One save path and one store, so the two
/// devices can't disagree about what was eaten, and no App Group is needed.
///
/// Each message carries an id, so a message delivered twice is saved once.
public enum WatchMessage: Codable, Equatable, Sendable {
    case log(id: UUID, text: String, at: Date)
    case water(id: UUID, millilitres: Double, at: Date)

    public var id: UUID {
        switch self {
        case .log(let id, _, _), .water(let id, _, _): return id
        }
    }

    /// The key a message travels under in a `WCSession` dictionary.
    public static let key = "vessel.message"

    public func encoded() throws -> [String: Any] {
        [Self.key: try JSONEncoder().encode(self)]
    }

    public init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.key] as? Data,
              let message = try? JSONDecoder().decode(WatchMessage.self, from: data)
        else { return nil }
        self = message
    }
}

/// Today, as the phone last saw it — what the watch face shows.
public struct WatchSummary: Codable, Equatable, Sendable {
    public var streakDays: Int
    public var mealsLogged: Int
    public var mealsRequired: Int
    /// Raw values of the meal slots already logged today.
    public var slotsLogged: [String]
    public var kilocalories: Double
    public var kilocalorieGoal: Double?
    public var waterML: Double
    public var waterGoalML: Double
    public var updatedAt: Date

    public init(
        streakDays: Int, mealsLogged: Int, mealsRequired: Int, slotsLogged: [String],
        kilocalories: Double, kilocalorieGoal: Double?, waterML: Double, waterGoalML: Double,
        updatedAt: Date
    ) {
        self.streakDays = streakDays
        self.mealsLogged = mealsLogged
        self.mealsRequired = mealsRequired
        self.slotsLogged = slotsLogged
        self.kilocalories = kilocalories
        self.kilocalorieGoal = kilocalorieGoal
        self.waterML = waterML
        self.waterGoalML = waterGoalML
        self.updatedAt = updatedAt
    }

    public static let key = "vessel.summary"

    public func encoded() throws -> [String: Any] {
        [Self.key: try JSONEncoder().encode(self)]
    }

    public init?(context: [String: Any]) {
        guard let data = context[Self.key] as? Data,
              let summary = try? JSONDecoder().decode(WatchSummary.self, from: data)
        else { return nil }
        self = summary
    }

    /// Whether this summary still describes today, or is a day behind.
    public func isCurrent(dayStart: Date) -> Bool { updatedAt >= dayStart }
}
