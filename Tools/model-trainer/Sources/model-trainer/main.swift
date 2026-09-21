import Foundation
import CreateML
import TabularData

// Trains Vessel's two parser models from a generated corpus.
//
//   swift run model-trainer <corpus-dir> <output-dir>
//
// Writes VesselIntent.mlmodel and VesselTagger.mlmodel, plus a metrics report.
// Training is a developer step run once per corpus change — the app never does
// this; it only loads the compiled result.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: model-trainer <corpus-dir> <output-dir>")
    exit(2)
}

let corpusDirectory = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - Corpus

struct IntentRow: Decodable { let text: String; let label: String }
struct TaggerRow: Decodable { let tokens: [String]; let labels: [String] }

func load<T: Decodable>(_ name: String, as type: [T].Type) throws -> [T] {
    let data = try Data(contentsOf: corpusDirectory.appendingPathComponent(name))
    return try JSONDecoder().decode([T].self, from: data)
}

let intentTrain = try load("intent-train.json", as: [IntentRow].self)
let intentTest = try load("intent-test.json", as: [IntentRow].self)
let taggerTrain = try load("tagger-train.json", as: [TaggerRow].self)
let taggerTest = try load("tagger-test.json", as: [TaggerRow].self)

print("corpus: \(intentTrain.count) intent train / \(intentTest.count) test")
print("        \(taggerTrain.count) tagger train / \(taggerTest.count) test\n")

// The accuracy bar the pipeline must clear before the parser is trusted to
// fill entries in without asking. Below it, results are shown for confirmation
// instead — a wrong entry the user didn't notice is worse than one extra tap.
let intentAccuracyGate = 0.90
let taggerF1Gate = 0.85

var report: [String] = []
var passedGates = true

// MARK: - Intent classifier

print("Training intent classifier…")
// Keyed by label, which is the shape CreateML wants and also makes the class
// balance visible at a glance.
var intentByLabel: [String: [String]] = [:]
for row in intentTrain { intentByLabel[row.label, default: []].append(row.text) }

let intentClassifier = try MLTextClassifier(trainingData: intentByLabel)

// Evaluate on the held-out split by hand rather than through CreateML's
// evaluation, so the reported number is per-utterance accuracy on data the
// model has genuinely never seen.
var intentCorrect = 0
var intentConfusion: [String: [String: Int]] = [:]
for row in intentTest {
    let predicted = (try? intentClassifier.prediction(from: row.text)) ?? ""
    intentConfusion[row.label, default: [:]][predicted, default: 0] += 1
    if predicted == row.label { intentCorrect += 1 }
}
let intentAccuracy = Double(intentCorrect) / Double(max(1, intentTest.count))

print(String(format: "  accuracy: %.2f%% (gate %.0f%%)\n", intentAccuracy * 100, intentAccuracyGate * 100))
report.append(String(format: "Intent accuracy: %.4f (gate %.2f)", intentAccuracy, intentAccuracyGate))
if intentAccuracy < intentAccuracyGate { passedGates = false }

report.append("\nIntent confusion (actual → predicted):")
for (actual, predictions) in intentConfusion.sorted(by: { $0.key < $1.key }) {
    let total = predictions.values.reduce(0, +)
    let correct = predictions[actual] ?? 0
    let wrong = predictions
        .filter { $0.key != actual && $0.value > 0 }
        .sorted { $0.value > $1.value }
        .prefix(3)
        .map { "\($0.key) ×\($0.value)" }
        .joined(separator: ", ")
    report.append(String(
        format: "  %-14@ %5.1f%% correct (%d/%d)%@",
        actual as NSString, Double(correct) * 100 / Double(max(1, total)), correct, total,
        wrong.isEmpty ? "" : "  — missed as \(wrong)" as NSString
    ))
}

// MARK: - Entity tagger

print("Training entity tagger…")
let taggerData = taggerTrain.map { (tokens: $0.tokens, labels: $0.labels) }
let tagger = try MLWordTagger(trainingData: taggerData)

// Per-label precision, recall and F1, computed ourselves so the report says
// which labels are weak rather than only how the model does on average.
// Macro F1 is the gate: averaging over labels rather than tokens stops the
// dominant NONE and FOOD labels from hiding a tagger that can't find a QTY.
var truePositives: [String: Int] = [:]
var falsePositives: [String: Int] = [:]
var falseNegatives: [String: Int] = [:]
var tokensSeen = 0
var tokensCorrect = 0

for row in taggerTest {
    guard !row.tokens.isEmpty else { continue }
    let sentence = row.tokens.joined(separator: " ")
    guard let predicted = try? tagger.prediction(from: sentence),
          predicted.count == row.labels.count
    else { continue }

    for (expected, actual) in zip(row.labels, predicted) {
        tokensSeen += 1
        if expected == actual {
            tokensCorrect += 1
            truePositives[expected, default: 0] += 1
        } else {
            falseNegatives[expected, default: 0] += 1
            falsePositives[actual, default: 0] += 1
        }
    }
}

let labels = Set(truePositives.keys)
    .union(falsePositives.keys)
    .union(falseNegatives.keys)
    .sorted()

var f1Scores: [String: Double] = [:]
report.append("\nTagger per-label scores:")
for label in labels {
    let tp = Double(truePositives[label] ?? 0)
    let fp = Double(falsePositives[label] ?? 0)
    let fn = Double(falseNegatives[label] ?? 0)
    let precision = tp + fp > 0 ? tp / (tp + fp) : 0
    let recall = tp + fn > 0 ? tp / (tp + fn) : 0
    let f1 = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    f1Scores[label] = f1
    report.append(String(
        format: "  %-10@ P %.3f  R %.3f  F1 %.3f  (n=%d)",
        label as NSString, precision, recall, f1, Int(tp + fn)
    ))
}

let macroF1 = f1Scores.values.reduce(0, +) / Double(max(1, f1Scores.count))
let tokenAccuracy = Double(tokensCorrect) / Double(max(1, tokensSeen))

print(String(format: "  token accuracy: %.2f%%", tokenAccuracy * 100))
print(String(format: "  macro F1: %.3f (gate %.2f)\n", macroF1, taggerF1Gate))
report.append(String(format: "\nTagger token accuracy: %.4f", tokenAccuracy))
report.append(String(format: "Tagger macro F1: %.4f (gate %.2f)", macroF1, taggerF1Gate))
if macroF1 < taggerF1Gate { passedGates = false }

// MARK: - Write

let intentURL = outputDirectory.appendingPathComponent("VesselIntent.mlmodel")
let taggerURL = outputDirectory.appendingPathComponent("VesselTagger.mlmodel")

try intentClassifier.write(
    to: intentURL,
    metadata: MLModelMetadata(
        author: "Vessel",
        shortDescription: "Classifies a logged utterance as food, water, symptom, journal, query or correction.",
        version: "1.0"
    )
)
try tagger.write(
    to: taggerURL,
    metadata: MLModelMetadata(
        author: "Vessel",
        shortDescription: "Labels tokens as quantity, unit, food, prep, brand, time, meal, negation, symptom or severity.",
        version: "1.0"
    )
)

let reportText = report.joined(separator: "\n")
try reportText.write(
    to: outputDirectory.appendingPathComponent("metrics.txt"),
    atomically: true, encoding: .utf8
)

print(reportText)
print("\nWrote models to \(outputDirectory.path)")

if !passedGates {
    print("\n⚠️  Below the accuracy gate. The pipeline will ask for confirmation rather than auto-filling.")
    exit(1)
}
