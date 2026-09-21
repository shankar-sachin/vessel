import Foundation
import VesselCore
import VesselNutrition

#if canImport(Vision)
import Vision
import CoreImage
#endif

/// What the camera made of a photo.
public struct PlateReading: Sendable {
    /// Candidate foods, best first.
    public let candidates: [FoodCandidate]
    /// Separate regions detected on the plate, when there was more than one.
    public let regionCount: Int
    /// Text read off packaging, which often names a product better than any
    /// classifier can.
    public let recognizedText: [String]

    public init(candidates: [FoodCandidate], regionCount: Int, recognizedText: [String]) {
        self.candidates = candidates
        self.regionCount = regionCount
        self.recognizedText = recognizedText
    }

    public var isEmpty: Bool { candidates.isEmpty && recognizedText.isEmpty }
}

/// One thing the classifier thinks it saw.
public struct FoodCandidate: Sendable, Identifiable, Equatable {
    public let id = UUID()
    /// A search term, already cleaned into words ("fried_egg" → "fried egg").
    public let label: String
    /// 0...1 from the classifier.
    public let confidence: Double
    /// The database row this resolved to, when the label named something the
    /// food database recognises.
    public let matched: FoodRecord?
    /// Fraction of the image this occupied, used for a rough portion guess.
    public let areaFraction: Double?

    public init(label: String, confidence: Double, matched: FoodRecord?, areaFraction: Double?) {
        self.label = label
        self.confidence = confidence
        self.matched = matched
        self.areaFraction = areaFraction
    }

    public static func == (lhs: FoodCandidate, rhs: FoodCandidate) -> Bool {
        lhs.label == rhs.label && lhs.confidence == rhs.confidence
    }
}

/// Recognises food in a photo.
///
/// ### Why this uses Apple's classifier rather than a trained one
///
/// Vision ships a 1,303-class image classifier with roughly fifty genuine food
/// categories — pizza, pasta, bread, cheese, egg, fried chicken, hamburger,
/// cake. That is *coarse*: it will say "fish", not "grilled salmon". A custom
/// model trained on Food-101 would be more specific, but it costs a multi-GB
/// download and training time, and it would still only know 101 things.
///
/// So the ordering here is deliberate, most reliable first: a **barcode** gives
/// exact nutrition, **text on packaging** usually names the product outright,
/// and **classification** is the last resort that narrows a home-cooked plate
/// down to something the user confirms. Presenting the coarse guess as though
/// it were a precise identification would be the dishonest option.
public struct FoodRecognizer: Sendable {

    private let search: FoodSearch

    public init(search: FoodSearch = FoodSearch()) {
        self.search = search
    }

    #if canImport(Vision)

    /// Classifier labels that aren't food, despite matching a food word.
    ///
    /// Vision's taxonomy contains "jellyfish", "goldfish", "dishwasher" and
    /// friends; without this a photo of an aquarium suggests logging fish.
    private static let notFood: Set<String> = [
        "angelfish", "clownfish", "jellyfish", "goldfish", "lionfish",
        "puffer_fish", "fishbowl", "fishtank", "fishing", "dishwasher",
        "juicer", "cakestand", "drinking_glass", "easter_egg", "eggplant_plant"
    ]

    /// Very general labels that are food but name nothing in particular.
    ///
    /// Kept only when there's no more specific candidate — "food" is true and
    /// useless if the classifier also said "pizza".
    private static let generic: Set<String> = ["food", "dish", "drink", "beverage", "snack", "dessert"]

    /// Anything below this is noise rather than a guess worth showing.
    private static let minimumConfidence = 0.08

    /// Decides whether an identifier names food, by asking the food database.
    ///
    /// A keyword list was the first approach and it was badly wrong: it kept
    /// "pizza" and "scrambled_eggs" but silently discarded banana, apple,
    /// broccoli, salmon, steak, avocado and most of the rest of Vision's actual
    /// food vocabulary, because none of those contain a word like "fruit" or
    /// "meat". Asking the database instead means the filter knows exactly as
    /// much as the app does, and stays right as the database changes.
    private func databaseMatch(for identifier: String) -> FoodRecord? {
        let term = Self.searchTerm(for: identifier)
        guard !Self.notFood.contains(identifier.lowercased()) else { return nil }

        guard let match = search.search(term, limit: 1).first else { return nil }
        // A weak fuzzy hit means the word merely resembles a food, not that it
        // is one — "dishwasher" should not resolve to a dish.
        guard match.score >= 0.45 else { return nil }
        return match.food
    }

    /// Reads a photo.
    ///
    /// The three passes run in sequence, not concurrently. `VNImageRequestHandler.perform`
    /// blocks, and the database lookups behind classification block on SQLite,
    /// so launching them with `async let` put three blocking calls onto the
    /// cooperative thread pool at once and deadlocked it. Concurrency buys
    /// nothing here anyway — the work is a few hundred milliseconds of CPU
    /// either way.
    ///
    /// The whole thing is hopped onto a background executor so a caller on the
    /// main actor doesn't freeze the UI while a photo is read.
    public func read(image: CIImage) async -> PlateReading {
        let recognizer = self
        return await Task.detached(priority: .userInitiated) {
            recognizer.readSynchronously(image: image)
        }.value
    }

    /// The actual work, all blocking.
    func readSynchronously(image: CIImage) -> PlateReading {
        PlateReading(
            candidates: classify(image),
            regionCount: detectRegions(image),
            recognizedText: recognizeText(image)
        )
    }

    // MARK: - Classification

    private func classify(_ image: CIImage) -> [FoodCandidate] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        guard (try? handler.perform([request])) != nil,
              let observations = request.results
        else { return [] }

        var specific: [FoodCandidate] = []
        var vague: [FoodCandidate] = []

        for observation in observations {
            guard Double(observation.confidence) >= Self.minimumConfidence else { continue }
            let identifier = observation.identifier.lowercased()

            if Self.generic.contains(identifier) {
                vague.append(FoodCandidate(
                    label: Self.searchTerm(for: identifier),
                    confidence: Double(observation.confidence),
                    matched: nil,
                    areaFraction: nil
                ))
                continue
            }

            guard let match = databaseMatch(for: observation.identifier) else { continue }
            specific.append(FoodCandidate(
                label: Self.searchTerm(for: observation.identifier),
                confidence: Double(observation.confidence),
                matched: match,
                areaFraction: nil
            ))
            if specific.count == 6 { break }
        }

        // "food" only helps when nothing better was found.
        return specific.isEmpty ? Array(vague.prefix(2)) : specific
    }

    /// "fried_egg" → "fried egg", so it can be searched against the database.
    static func searchTerm(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Regions

    /// Counts visually distinct areas of interest.
    ///
    /// Saliency rather than object detection: Vision has no food-aware detector,
    /// and saliency at least separates two things sitting apart on a plate. It
    /// genuinely cannot separate the components of a stew, which is why the
    /// count is offered as a hint ("looks like 3 things") rather than used to
    /// split the entry automatically.
    private func detectRegions(_ image: CIImage) -> Int {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let objects = observation.salientObjects
        else { return 0 }

        // Overlapping boxes are the same thing seen twice.
        var kept: [CGRect] = []
        for object in objects.sorted(by: { $0.confidence > $1.confidence }) {
            let box = object.boundingBox
            guard box.width > 0.05, box.height > 0.05 else { continue }
            let overlaps = kept.contains { $0.intersects(box) && $0.intersection(box).area > box.area * 0.4 }
            if !overlaps { kept.append(box) }
        }
        return kept.count
    }

    // MARK: - Text

    /// Reads text off packaging.
    ///
    /// Often the single most useful signal for a packaged item: a product name
    /// printed on a wrapper identifies it far more precisely than any general
    /// classifier, and unlike a barcode it survives being photographed at an
    /// angle.
    private func recognizeText(_ image: CIImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results
        else { return [] }

        return observations
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence > 0.4 }
            .map(\.string)
            // Single characters and stray numbers are packaging noise.
            .filter { $0.count >= 3 && $0.rangeOfCharacter(from: .letters) != nil }
            .prefix(8)
            .map { $0 }
    }

    #else

    public func read(image: Any) async -> PlateReading {
        PlateReading(candidates: [], regionCount: 0, recognizedText: [])
    }

    #endif
}

#if canImport(Vision)
private extension CGRect {
    var area: CGFloat { width * height }
}
#endif
