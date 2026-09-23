#!/usr/bin/env bash
# Clean-installs the app, runs the UI suite, and exports every screenshot the
# tests attach (capture("02-water-midpour") …) under its human name into
# build/screenshots/. Watch pages are captured separately via -page.
#
#   scripts/screenshots.sh              iPhone + Watch
#   scripts/screenshots.sh --only Tour  one test class, e.g. TourUITests

source "$(dirname "$0")/lib.sh"

ONLY=()
if [[ "${1:-}" == "--only" ]]; then ONLY=(-only-testing:"VesselUITests/${2}UITests"); fi

OUT="$ROOT/build/screenshots"; RAW="$ROOT/build/shots-raw"
rm -rf "$OUT" "$RAW" build/ui.xcresult; mkdir -p "$OUT"
PHONE="$(device_id "$IPHONE_NAME")"

step "Clean install on $IPHONE_NAME"
xcrun simctl boot "$PHONE" 2>/dev/null || true
xcrun simctl uninstall "$PHONE" com.sachinshankar.vessel || true
xcodegen generate --quiet

step "Running the UI suite (10–20 minutes for the full run)"
xcodebuild -project Vessel.xcodeproj -scheme Vessel -destination "id=$PHONE" \
  -resultBundlePath build/ui.xcresult ${ONLY[@]+"${ONLY[@]}"} test >build/ui.log 2>&1 \
  || echo "Some UI tests failed — exporting what was captured (see build/ui.log)." >&2

step "Exporting attachments"
xcrun xcresulttool export attachments --path build/ui.xcresult --output-path "$RAW"
python3 - "$RAW" "$OUT" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1:]
count = 0
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for a in test.get("attachments", []):
        human = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        # xcresulttool appends "_0_<UUID>" to the name the test gave.
        human = re.sub(r"_\d+_[0-9A-F-]{36}", "", human)
        shutil.copy(os.path.join(raw, a["exportedFileName"]), os.path.join(out, human))
        count += 1
print(f"{count} screenshots → {out}")
PY

step "Apple Watch pages"
WATCH="$(device_id "$WATCH_NAME")"
xcrun simctl boot "$WATCH" 2>/dev/null || true
WLOG=build/watch-build.log
xcodebuild -project Vessel.xcodeproj -scheme VesselWatch -configuration Debug \
  -destination "id=$WATCH" -derivedDataPath build/watch-derived build >"$WLOG" 2>&1 \
  || { tail -20 "$WLOG" >&2; false; }
xcrun simctl install "$WATCH" "$(find build/watch-derived/Build/Products -name 'Vessel.app' -path '*watchsimulator*' | head -1)"
for page in today water log; do
  xcrun simctl terminate "$WATCH" com.sachinshankar.vessel.watchkitapp 2>/dev/null || true
  xcrun simctl launch "$WATCH" com.sachinshankar.vessel.watchkitapp -page "$page" -sample >/dev/null
  sleep 3
  xcrun simctl io "$WATCH" screenshot "$OUT/watch-$page.png" >/dev/null
done
ok "Screenshots in build/screenshots/"
