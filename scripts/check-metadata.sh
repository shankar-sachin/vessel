#!/usr/bin/env bash
# Builds the app and asserts that what the system will actually see — the App
# Intents metadata extracted at build time — lists every intent, entity, enum
# and App Shortcut. A compile that succeeds says nothing about this.

source "$(dirname "$0")/lib.sh"

DERIVED="$ROOT/build/metadata-derived"

step "Building for $IPHONE_NAME"
xcodegen generate --quiet
xcodebuild -project Vessel.xcodeproj -scheme Vessel -configuration Debug \
  -destination "id=$(device_id "$IPHONE_NAME")" -derivedDataPath "$DERIVED" \
  build >"$ROOT/build/metadata-build.log" 2>&1 || { tail -30 "$ROOT/build/metadata-build.log" >&2; false; }

step "Reading extract.actionsdata"
DATA="$(find "$DERIVED/Build/Products" -path '*Vessel.app/Metadata.appintents/extract.actionsdata' | head -1)"
[[ -n "$DATA" ]] || { echo "no extract.actionsdata in the built app" >&2; false; }

python3 - "$DATA" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))

def names(section):
    v = j.get(section, {})
    return set(v.keys()) if isinstance(v, dict) else {e.get("identifier") or e.get("name") for e in v}

expected = {
    "actions": {"LogIntent", "LogWaterIntent", "LogSymptomIntent", "AddJournalEntryIntent",
                "CheckIntakeIntent", "OpenMealIntent", "CreateJournalEntryIntent"},
    "entities": {"FoodEntity", "MealEntity", "JournalEntryEntity"},
}
failed = False
for section, want in expected.items():
    have = names(section)
    missing = sorted(want - have)
    print(f"{section}: {len(have)} found" + (f", MISSING {missing}" if missing else ""))
    failed |= bool(missing)

enums = names("enums")
print(f"enums: {sorted(enums)}")
failed |= not enums

shortcuts = j.get("autoShortcuts") or j.get("appShortcuts") or []
print(f"app shortcuts: {len(shortcuts)}")
if len(shortcuts) < 5:
    print("expected at least 5 App Shortcuts"); failed = True
sys.exit(1 if failed else 0)
PY
ok "Every intent, entity, enum and shortcut is in the metadata."
