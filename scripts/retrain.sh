#!/usr/bin/env bash
# Regenerates the training corpus, retrains both parser models, installs them,
# and judges the result on RealPhrasingTests — the hand-written eval, not the
# training report (see CLAUDE.md: the training numbers mostly measure the
# generator's own grammar).
#
#   scripts/retrain.sh [sentences]    default 50000
#
# The eval runs twice. A flat classifier output once made the score move with
# no code change; two runs that disagree mean that is back.

source "$(dirname "$0")/lib.sh"

COUNT="${1:-50000}"
DB=Packages/VesselNutrition/Sources/VesselNutrition/Resources/foods.sqlite
DEST=Packages/VesselIntelligence/Sources/VesselIntelligence/Resources
CORPUS="$(mktemp -d)/corpus"
GATE=90.0

step "Building corpus-gen and model-trainer"
swift build -c release --package-path Tools/corpus-gen
swift build -c release --package-path Tools/model-trainer

step "Generating $COUNT sentences (through the app's TextNormalizer)"
./Tools/corpus-gen/.build/release/corpus-gen "$DB" "$CORPUS" "$COUNT"

step "Training (a few minutes; fails below 90% intent / 0.85 macro F1)"
./Tools/model-trainer/.build/release/model-trainer "$CORPUS" Resources/Models

step "Installing the models"
cp Resources/Models/*.mlmodel "$DEST/"

eval_once() {
  swift test --package-path Packages/VesselIntelligence --filter RealPhrasingTests 2>&1 \
    | tee "$1" | grep -E 'REAL-PHRASING' || true
  grep -oE 'REAL-PHRASING intent accuracy: [0-9.]+' "$1" | grep -oE '[0-9.]+$'
}

step "RealPhrasingTests, run 1"
first="$(eval_once build/eval-1.log | tail -1)"
step "RealPhrasingTests, run 2"
second="$(eval_once build/eval-2.log | tail -1)"

step "Judging"
echo "intent accuracy: run 1 = $first%, run 2 = $second%"
[[ "$first" == "$second" ]] || { echo "The two runs disagree — the eval is nondeterministic." >&2; false; }
python3 -c "import sys; sys.exit(0 if float('$first') >= $GATE else 1)" \
  || { echo "Intent accuracy $first% is below the $GATE% gate." >&2; false; }
ok "Models installed. Intent $first% on hand-written phrasings, stable across runs."
