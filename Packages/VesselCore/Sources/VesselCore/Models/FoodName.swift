import Foundation

/// A database food name, rearranged the way a person would say it.
///
/// USDA names put the head noun first so they sort — "Rice, white, cooked, no
/// added fat" — which reads like a filing cabinet when it lands in a meal log.
/// One rule turns most of them round: a single-word second clause that names
/// a *kind* ("white", "Cheddar", "ground") goes in front of the head, and
/// everything else becomes a quiet detail line. A clause that names a *state*
/// ("raw", "cooked", "frozen") stays in the detail, because "Raw egg" is not
/// what anyone calls an egg they are about to boil.
///
/// Works on the stored string, so meals logged long before this existed read
/// the same way.
public struct FoodName: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    public init(_ raw: String) {
        let clauses = raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !Self.isUnspecified($0) }
            .map { $0.replacingOccurrences(of: " or NFS", with: "") }

        guard var head = clauses.first else {
            title = raw
            detail = nil
            return
        }
        var rest = Array(clauses.dropFirst())

        if let kind = rest.first, Self.isKind(kind) {
            // "Nuts, almonds": a plural second clause is the food itself, and
            // the head was only its aisle.
            let isPlural = kind.hasSuffix("s") && !kind.hasSuffix("ss") && !kind.hasSuffix("'s")
            head = isPlural ? Self.capitalizingFirst(kind)
                            : Self.capitalizingFirst(kind) + " " + head.lowercased()
            rest.removeFirst()
        }

        title = head
        detail = rest.isEmpty ? nil : rest.joined(separator: " · ")
    }

    /// One word, not a state of preparation.
    ///
    /// States are spotted by shape rather than listed: English marks nearly
    /// all of them as past participles ("cooked", "baked", "unsweetened"), and
    /// the handful that aren't are few enough to name.
    private static func isKind(_ clause: String) -> Bool {
        let words = clause.split(separator: " ")
        guard words.count == 1, let word = words.first?.lowercased(), word.count > 2 else { return false }
        if word.hasSuffix("ed") || word.hasSuffix("en") { return false }
        return !["raw", "fresh", "dry", "prepared", "canned", "instant", "homemade"].contains(word)
    }

    private static func isUnspecified(_ clause: String) -> Bool {
        clause.contains("NS as to") || clause == "NFS"
    }

    private static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
