import Foundation

// Generates Vessel's parser training corpus.
//
//   swift run corpus-gen <foods.sqlite> <output-dir> [count]
//
// Writes three files Create ML consumes directly:
//   intent-train.json / intent-test.json   — text → intent label
//   tagger-train.json / tagger-test.json   — tokens → per-token labels
//   corpus-sample.txt                      — human-readable sample for review

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("""
    usage: corpus-gen <foods.sqlite> <output-dir> [count]

      <foods.sqlite>  the compiled food database
      <output-dir>    where to write the corpus
      [count]         utterances to generate (default 50000)
    """)
    exit(2)
}

let databaseURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
let count = arguments.count > 3 ? (Int(arguments[3]) ?? 50_000) : 50_000

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Draw from the most commonly logged foods. Using all 11,750 would fill the
// corpus with entries nobody ever types and starve the common ones of examples.
let foods = try FoodLoader.load(from: databaseURL, limit: 3_000)
print("· vocabulary: \(foods.count) food names")

// Fixed seed: the same corpus every run, so a change in model accuracy is
// attributable to the model rather than to different training data.
let corpusSeed: UInt64 = 0x5645_5353_454C_0001
var generator = Generator(foods: foods, seed: corpusSeed)
let examples = generator.generate(count: count)
print("· generated: \(examples.count) utterances")

// Hold out 10% for evaluation. Split by hash of the text rather than by
// position so the same sentence always lands on the same side, making the
// accuracy figures comparable between runs.
func isHeldOut(_ example: Example) -> Bool {
    abs(example.text.hashValue) % 10 == 0
}

let test = examples.filter(isHeldOut)
let train = examples.filter { !isHeldOut($0) }
print("· split: \(train.count) train / \(test.count) test")

// MARK: - Writing

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

struct IntentRow: Encodable { let text: String; let label: String }
struct TaggerRow: Encodable { let tokens: [String]; let labels: [String] }

func writeIntent(_ examples: [Example], to name: String) throws {
    let rows = examples.map { IntentRow(text: $0.text, label: $0.intent.rawValue) }
    try encoder.encode(rows).write(to: outputDirectory.appendingPathComponent(name))
}

func writeTagger(_ examples: [Example], to name: String) throws {
    let rows = examples.map {
        TaggerRow(tokens: $0.tokens, labels: $0.labels.map(\.rawValue))
    }
    try encoder.encode(rows).write(to: outputDirectory.appendingPathComponent(name))
}

try writeIntent(train, to: "intent-train.json")
try writeIntent(test, to: "intent-test.json")
try writeTagger(train, to: "tagger-train.json")
try writeTagger(test, to: "tagger-test.json")

// A readable sample, because the fastest way to spot a broken grammar rule is
// to look at what it produced.
let sample = examples.prefix(40).map { example -> String in
    let pairs = zip(example.tokens, example.labels)
        .map { "\($0)/\($1.rawValue)" }
        .joined(separator: " ")
    return "[\(example.intent.rawValue)] \(example.text)\n    \(pairs)"
}.joined(separator: "\n\n")
try sample.write(to: outputDirectory.appendingPathComponent("corpus-sample.txt"), atomically: true, encoding: .utf8)

// MARK: - Summary

var intentCounts: [String: Int] = [:]
for example in examples { intentCounts[example.intent.rawValue, default: 0] += 1 }

var labelCounts: [String: Int] = [:]
for example in examples {
    for label in example.labels { labelCounts[label.rawValue, default: 0] += 1 }
}

print("\nIntents")
for (intent, n) in intentCounts.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-14s %6d  %5.1f%%", (intent as NSString).utf8String!, n, Double(n) * 100 / Double(examples.count)))
}
print("\nToken labels")
for (label, n) in labelCounts.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-10s %7d", (label as NSString).utf8String!, n))
}
print("\nWrote corpus to \(outputDirectory.path)")
