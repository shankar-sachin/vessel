import Foundation
import VesselIntelligence

/// Puts each generated sentence through the app's own normalizer.
///
/// The models never see what a person typed. They see what `TextNormalizer`
/// made of it: lead-ins and fillers dropped, time phrases lifted out, commas
/// removed, "quarter" rewritten as 0.25. A corpus written in the raw surface
/// form therefore trains on sentences that never occur at inference, and the
/// gap between the two has caused a failure every time it opened:
///
/// - "a beer with dinner" reached the tagger as "a beer with", because the time
///   parser took "dinner" and left the preposition. The corpus only ever had
///   "with dinner" whole, so the stray "with" was read as part of the drink.
/// - The corpus wrote "cereal , orange juice" with the comma as a token. The
///   normalizer drops commas, so the tagger learned a separator it would never
///   be shown.
/// - "a quarter of a melon" became "a 0.25 of a melon", a decimal in a position
///   the corpus had only ever filled with a word.
///
/// Each was fixed by hand, one at a time, by teaching the generator to imitate
/// the normalizer. Running the real one instead closes the whole class: the
/// corpus now changes whenever the normalizer does.
enum CorpusNormalizer {

    private static let normalizer = TextNormalizer(calendar: Calendar(identifier: .gregorian))
    /// Fixed so the corpus is reproducible; only the *tokens* matter here.
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// The example as the models will meet it, or nil if nothing survives.
    static func apply(_ example: Example) -> Example? {
        // Re-tokenize each source token the way the normalizer will ("i'm" →
        // "im"), carrying its label onto every piece.
        var source: [String] = []
        var sourceLabels: [Grammar.Label] = []
        for (token, label) in zip(example.tokens, example.labels) {
            for piece in TextNormalizer.tokenize(token) {
                source.append(piece)
                sourceLabels.append(label)
            }
        }

        let target = normalizer.normalize(source.joined(separator: " "), now: now).tokens
        guard !target.isEmpty else { return nil }

        return Example(
            tokens: target,
            labels: align(source: source, labels: sourceLabels, target: target),
            intent: example.intent
        )
    }

    /// Carries labels from the source tokens onto the normalized ones.
    ///
    /// Tokens the normalizer left alone line up through their longest common
    /// subsequence. What remains are rewrites — "two and a half" → "2.5",
    /// "a couple of" → "2" — and each takes the label of the source tokens it
    /// replaced, preferring a meaningful label over NONE.
    static func align(source: [String], labels: [Grammar.Label], target: [String]) -> [Grammar.Label] {
        let n = source.count, m = target.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = source[i] == target[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var result = Array(repeating: Grammar.Label.none, count: m)
        var i = 0, j = 0
        var gapSource: [Grammar.Label] = []
        var gapTarget: [Int] = []

        func closeGap() {
            let label = gapSource.first { $0 != .none } ?? .none
            for index in gapTarget { result[index] = label }
            gapSource = []
            gapTarget = []
        }

        while i < n && j < m {
            if source[i] == target[j] {
                closeGap()
                result[j] = labels[i]
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                gapSource.append(labels[i]); i += 1
            } else {
                gapTarget.append(j); j += 1
            }
        }
        while i < n { gapSource.append(labels[i]); i += 1 }
        while j < m { gapTarget.append(j); j += 1 }
        closeGap()
        return result
    }
}
