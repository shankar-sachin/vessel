# Vessel

A food, water, journal and symptom diary for iOS and iPadOS, built around one
idea: **logging that you felt bloated is nearly useless on its own, and genuinely
useful next to a timestamped record of everything you ate in the previous day.**

That connection is why all four logs live in one app instead of four.

Everything runs on your device. There is no account, no server, and no
telemetry. The only network call Vessel ever makes is a barcode lookup you
explicitly ask for.

---

## What it does

**Diet Tracker** — Describe a meal the way you'd say it out loud and Vessel
works out the rest. Type it, speak it, photograph it, or scan a barcode.

**Water Diary** — One-tap logging against a goal, with a liquid that actually
moves when you pour into it.

**Journal** — Somewhere to write about the day, set in a serif face because it's
meant for reading rather than scanning.

**Date Log** — Digestive and dietary reactions, recorded against *when they
started* rather than when you got around to typing them, because that's what
makes correlating them against food possible.

**Streaks** — Three meals a day by default, or whatever matches how you actually
eat: two meals, OMAD, 16:8, 18:6, or your own. A Live Activity counts down in
the Dynamic Island before the day resets.

---

## The parser

Vessel ships a small language model, purpose-built for this one job and trained
from scratch:

- an **intent classifier** — meal, drink, reaction, journal note, question, or correction
- a **CRF entity tagger** — quantity, unit, food, preparation, brand, time, meal, negation, symptom, severity

Both are Core ML, about **1 MB together**, and run entirely offline.

Around them sits a pipeline that does the deterministic work in plain Swift —
"two and a half" → `2.5`, "this morning" → a real timestamp, splitting "eggs and
toast" into two foods — because those have exactly one right answer and learning
them from data would be strictly worse. The models handle only the genuinely
ambiguous parts, and if one fails to load the pipeline falls back to rules rather
than leaving you unable to log a meal.

### How it was trained

`Tools/corpus-gen` **generates its own training data**: 50,000 labelled
utterances from a hand-written grammar crossed with real food names from the
bundled database. Because the generator knows what it emitted, per-token labels
come for free. Hand-labelling 50,000 sentences is a project; writing the grammar
was an afternoon.

### How well it works

| | Synthetic (same generator) | **Hand-written real phrasings** |
|---|---|---|
| Intent accuracy | 99.4% | **90.1%** (64/71) |
| Food extraction | — | **96.3%** (26/27) |
| Quantity accuracy | — | **100%** |
| Tagger macro F1 | 0.986 | — |

The right-hand column is the one that means anything. The synthetic numbers
mostly prove the model learned the grammar it was taught, so the evaluation set
is 71 utterances written by hand in shapes the generator never produces. When
that set was expanded from 51 cases to 71 the score *dropped* from 94.1% to
90.1% — the first number was flattered by a set partly designed around it.

**The parse is always shown before it's saved.** A parser that fills entries in
invisibly is only pleasant while it's right; the moment it's wrong you've logged
food you never ate, you won't notice for weeks, and by then the correlations are
built on it.

---

## The food database

**11,750 foods**, 5.4 MB, bundled and searchable offline with FTS5.

`Tools/db-builder` compiles three USDA FoodData Central datasets into one SQLite
file — SR Legacy for breadth, Foundation for lab-quality figures, and FNDDS for
names written the way people speak ("Milk, whole" rather than "Milk, whole,
3.25% milkfat, with added vitamin D"). It also derives per-food densities, so a
cup of rice and a cup of milk resolve to different weights.

Foods carry ingredient tags — dairy, gluten, allium, nightshade — which is what
lets the Date Log say *dairy* correlates with bloating rather than *pizza* does.

---

## Your data

Vessel keeps everything on your device, which is good for privacy and bad for
lost phones. So:

- **Export** the whole database as plain JSON, readable by anything
- **Import** merges by id rather than replacing, so nothing is lost or duplicated
- **Automatic backup** to a folder you choose — point it at iCloud Drive and your
  devices share data with no paid membership and no CloudKit entitlement

That last one is eventual, file-level sharing rather than live sync: edit the
same entry on two devices and the one already there wins. Real conflict
resolution is what CloudKit would buy, and the schema is already written to its
rules so enabling it later is a two-line change.

---

## Building

Requires Xcode 26 or later. The Xcode project is **generated** — `project.yml`
is the source of truth.

```sh
brew install xcodegen
xcodegen generate
open Vessel.xcodeproj
```

Targets iOS/iPadOS 18, with a fuller experience on 26+ (on-device foundation
models as a parsing fallback, streaming transcription, Liquid Glass). iOS 18 is
a complete app, not a crippled one.

### Layout

| Package | Holds |
|---|---|
| `VesselCore` | SwiftData models, persistence, streak engine, capability gating |
| `VesselDesign` | Palette, typography, motion, shared components |
| `VesselNutrition` | The food database, Open Food Facts client, portion resolver |
| `VesselIntelligence` | The language model, parsing pipeline, voice transcription |
| `VesselVision` | Barcode, packaging text, image recognition |
| `VesselActivities` | Live Activity attributes, shared with the widget extension |
| `VesselInsights` | Symptom↔food correlation *(in progress)* |
| `VesselIntents` | App Intents / Siri *(in progress)* |

Build-time tools in `Tools/` regenerate the food database and retrain the
parser; see `CLAUDE.md` for the exact commands and the traps worth knowing about.

---

## Status

Working: all four logs, the parser, the food database, voice, camera, streaks
and Live Activities, backup and export.

In progress: the correlation engine, Siri, and a watchOS app.

**Not yet verified on hardware:** voice transcription and the Dynamic Island's
rendering. Both are implemented and unit-tested, but a simulator has no
microphone and doesn't render Live Activity content reliably.

---

## Licence

[Apache 2.0](LICENSE).

Nutrition data comes from [USDA FoodData Central](https://fdc.nal.usda.gov)
(public domain). Packaged product data comes from
[Open Food Facts](https://world.openfoodfacts.org), used under the
[Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).

Vessel is a personal diary, not a medical device. It records what you tell it and
looks for patterns in it. Anything it suggests is an observation about your own
data, never a diagnosis.
