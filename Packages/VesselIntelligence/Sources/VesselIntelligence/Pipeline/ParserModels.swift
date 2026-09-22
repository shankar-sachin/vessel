import Foundation
import CoreML
import NaturalLanguage

/// Loads and runs the two trained models.
///
/// Both are optional at runtime. If a model is missing or fails to load, the
/// pipeline falls back to its rule-based path rather than refusing to parse —
/// a user whose model file didn't ship should still be able to log a meal.
public final class ParserModels: @unchecked Sendable {

    public static let shared = ParserModels()

    private let intentModel: NLModel?
    private let taggerModel: NLModel?

    /// True when both models loaded. Exposed so the UI can explain reduced
    /// behaviour rather than silently being worse.
    public var isFullyLoaded: Bool { intentModel != nil && taggerModel != nil }
    public var hasIntentModel: Bool { intentModel != nil }
    public var hasTaggerModel: Bool { taggerModel != nil }

    public init() {
        intentModel = Self.load("VesselIntent")
        taggerModel = Self.load("VesselTagger")
    }

    private static func load(_ name: String) -> NLModel? {
        // SPM compiles .mlmodel resources to .mlmodelc at build time.
        guard let url = Bundle.module.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.module.url(forResource: name, withExtension: "mlmodel"),
              let model = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: model)
        else { return nil }
        return nlModel
    }

    // MARK: - Inference

    /// The classifier's best guess, with how confident it is.
    ///
    /// Confidence matters as much as the label: the pipeline uses a low score
    /// to decide it should ask rather than assume.
    public func predictIntent(_ text: String) -> (label: String, confidence: Double)? {
        guard let intentModel, !text.isEmpty else { return nil }

        let hypotheses = intentModel.predictedLabelHypotheses(for: text, maximumCount: 2)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else {
            return intentModel.predictedLabel(for: text).map { ($0, 0.5) }
        }

        // A confident classifier puts most of its mass on one label. When the
        // top two are close the answer is really "I don't know", and reporting
        // the raw top score would hide that.
        let runnerUp = hypotheses.filter { $0.key != best.key }.values.max() ?? 0
        let margin = best.value - runnerUp

        // No opinion at all. Every word was unseen, the distribution came
        // back flat, and "best" is whichever label the dictionary happened to
        // yield first — a different answer on different runs. Returning nil
        // hands the decision to the rule-based classifier, which is at least
        // deterministic and knows the symptom vocabulary.
        if margin < 0.005 { return nil }

        return (best.key, min(1.0, best.value * (0.6 + 0.4 * margin)))
    }

    /// Per-token labels for a sentence.
    ///
    /// - Returns: one label per token, aligned with `tokens`, or nil if the
    ///   model is unavailable or disagreed about the token count.
    public func tagTokens(_ tokens: [String]) -> [String]? {
        guard let taggerModel, !tokens.isEmpty else { return nil }

        let sentence = tokens.joined(separator: " ")
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sentence
        tagger.setModels([taggerModel], forTagScheme: .nameType)

        var labels: [String] = []
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            labels.append(tag?.rawValue ?? "NONE")
            return true
        }

        // Alignment is not guaranteed: NaturalLanguage tokenizes by its own
        // rules, which can split or merge differently from ours. A misaligned
        // label array is worse than none, because it would attach a quantity to
        // the wrong word.
        return labels.count == tokens.count ? labels : nil
    }
}
