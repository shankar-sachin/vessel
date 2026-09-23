#!/usr/bin/env bash
# Rebuilds foods.sqlite from the USDA FoodData Central CSV dumps, then runs the
# nutrition tests, which check search quality and tags against the real file.
#
#   scripts/rebuild-db.sh <extracted-csv-dir>
#   scripts/rebuild-db.sh --reindex     re-derive head nouns on the existing
#                                       database, no CSVs needed
#
# The CSV dir holds the extracted Foundation, SR Legacy and Survey (FNDDS)
# dumps from https://fdc.nal.usda.gov/fdc-datasets/.

source "$(dirname "$0")/lib.sh"

DB=Packages/VesselNutrition/Sources/VesselNutrition/Resources/foods.sqlite
[[ $# -eq 1 ]] || { sed -n '2,11p' "$0" >&2; exit 2; }

step "Building db-builder"
swift build -c release --package-path Tools/db-builder
BUILDER=./Tools/db-builder/.build/release/db-builder

if [[ "$1" == "--reindex" ]]; then
  step "Re-deriving head nouns in place"
  "$BUILDER" --reindex "$DB"
else
  [[ -d "$1" ]] || { echo "not a directory: $1" >&2; exit 2; }
  step "Building foods.sqlite from $1"
  "$BUILDER" "$1" "$DB"
fi
ls -lh "$DB"

step "VesselNutrition tests (search quality, tags, EverydayQueryTests)"
swift test --package-path Packages/VesselNutrition
ok "Database rebuilt and verified."
